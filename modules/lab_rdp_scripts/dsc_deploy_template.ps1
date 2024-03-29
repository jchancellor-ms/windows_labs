#####################################################################################
# Generate the credential objects - 
# !!NOTE: This is for a lab.  If doing this in production, these need to be encyrpted
#####################################################################################
[PSCredential]$AdminCredential = New-Object System.Management.Automation.PSCredential(("${domain_name}" + "\" + "${admin_user}"), ( "${admin_password}" | ConvertTo-SecureString -asPlainText -Force ))
[PSCredential]$credentialObjectSql = New-Object System.Management.Automation.PSCredential( "${sql_admin}", ( "${sql_password}"  | ConvertTo-SecureString -AsPlainText -Force ))

#########################################################################
# Configure the node LCM configuration to allow for reboots
#########################################################################
[DSCLocalConfigurationManager()]
Configuration lcmConfig {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]$NodeName
    )

    Node $NodeName
    {
        Settings
        {
            RefreshMode = 'Push'
            ActionAfterReboot = "ContinueConfiguration"
            RebootNodeIfNeeded = $true
            ConfigurationModeFrequencyMins = 15
        }
    }
}

$hosts = @(${all_hosts})

Write-Host "Creating mofs"
foreach ($hostname in $hosts) {
    lcmConfig -NodeName $hostname -OutputPath .\lcmConfig
    $cim = New-CimSession -ComputerName $hostname -Credential $AdminCredential
    Set-DscLocalConfigurationManager -CimSession $cim -Path .\lcmConfig -Verbose
    Get-DscLocalConfigurationManager -CimSession $cim
}

#########################################################################
# Define the Configurations
#########################################################################
Configuration rdsHAConfig {
    #########################################################################
    # Import the DSC modules used in the configuration
    ########################################################################
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ActiveDirectoryDsc
    Import-DscResource -ModuleName DnsServerDsc
    Import-DscResource -ModuleName @{ModuleName = "xRemoteDesktopSessionHost"; RequiredVersion = "2.1.0" }
    Import-DscResource -ModuleName SqlServerDsc
    Import-DscResource -ModuleName SecurityPolicyDsc
    Import-DscResource -ModuleName ComputerManagementDsc
    Import-DscResource -ModuleName WebAdministrationDsc
    Import-DSCResource -Name WindowsFeature
  
    
    #########################################################################
    # Configure the Script Host and the initial farm and HA configurations
    #########################################################################

    Node $AllNodes.Where{ $_.Role -contains "Script" }.NodeName
    {
        LocalConfigurationManager 
        {
            RebootNodeIfNeeded = $true
        }
        
        #Add the RSAT tools for the AD and DNS features
        WindowsFeature 'Rsat-ADDS'
        {
            Name                 = 'RSAT-ADDS'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }

        WindowsFeature 'Rsat-DNS-Server'
        {
            Name                 = 'RSAT-DNS-Server'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }
        
        WindowsFeature 'Rsat-AD-Powershell'
        {
            Name                 = 'RSAT-AD-Powershell'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }

        File ConfigurationFolder {
            Type = "Directory"
            DestinationPath = "c:\temp"
            Ensure = "Present"
        }

        #Create AD groups for each role type and add the members 
        #TODO: Determine if the non-broker roles are still needed
        #Currently only the broker group is used in the config
        ADGroup 'BrokerGroup'
        {
            GroupName          = $ConfigurationData.RDSConfig.BrokerGroupName
            GroupScope         = 'Global'
            Category           = 'Security'
            Description        = 'Group for the Connection Broker Machines'
            Ensure             = 'Present'
            MembersToInclude   = $ConfigurationData.RDSConfig.GroupBrokerHosts
            Credential         = $AdminCredential
        }
        
        ADGroup 'SessionGroup'
        {
            GroupName   = $ConfigurationData.RDSConfig.SessionGroupName
            GroupScope  = 'Global'
            Category    = 'Security'
            Description = 'Group for the Session Machines'
            Ensure      = 'Present'
            MembersToInclude =  $ConfigurationData.RDSConfig.GroupSessionHosts
            Credential = $AdminCredential
        }

        ADGroup 'GatewayGroup'
        {
            GroupName   = $ConfigurationData.RDSConfig.GatewayGroupName
            GroupScope  = 'Global'
            Category    = 'Security'
            Description = 'Group for the Gateway Machines'
            Ensure      = 'Present'
            MembersToInclude = $ConfigurationData.RDSConfig.GroupGatewayHosts
            Credential = $AdminCredential
        }

        ADGroup 'WebGroup'
        {
            GroupName   = $ConfigurationData.RDSConfig.WebGroupName
            GroupScope  = 'Global'
            Category    = 'Security'
            Description = 'Group for the Web Machines'
            Ensure      = 'Present'
            MembersToInclude = $ConfigurationData.RDSConfig.GroupWebHosts
            Credential = $AdminCredential
        }

        #Create DNS records for the configuration
        DnsRecordA 'BrokerLBDns'
        {
            ZoneName    = $ConfigurationData.RDSConfig.DomainFqdn
            Name        = $ConfigurationData.RDSConfig.BrokerRecordName 
            IPv4Address = $ConfigurationData.RDSConfig.BrokerLbIpAddress
            TimeToLive  = '01:00:00'
            DnsServer   = $ConfigurationData.RDSConfig.DomainFqdn
            Ensure      = 'Present'
            PsDscRunAsCredential = $AdminCredential
        }

        DnsRecordA 'GatewayLBDns'
        {
            ZoneName    = $ConfigurationData.RDSConfig.DomainFqdn
            Name        = $ConfigurationData.RDSConfig.GatewayRecordName 
            IPv4Address = $ConfigurationData.RDSConfig.GatewayLbIpAddress
            TimeToLive  = '01:00:00'
            DnsServer   = $ConfigurationData.RDSConfig.DomainFqdn
            Ensure      = 'Present'
            PsDscRunAsCredential = $AdminCredential
        }

        DnsRecordA 'WebLBDns'
        {
            ZoneName             = $ConfigurationData.RDSConfig.DomainFqdn
            Name                 = $ConfigurationData.RDSConfig.WebRecordName 
            IPv4Address          = $ConfigurationData.RDSConfig.WebLbIpAddress
            TimeToLive           = '01:00:00'
            DnsServer            = $ConfigurationData.RDSConfig.DomainFqdn
            Ensure               = 'Present'
            PsDscRunAsCredential = $AdminCredential
        }       
       

        # Add the admin domain user as sysadmin in SQL.  This allows us to use the SqlDSC for other SQL logins 
        # TODO: Figure out why the SQL DSC isn't able to use the SQL authentication login. Clean-up the credential objects to only SQL?
        # Alternately this could be run on the SQL node, but I didn't want to assume that SQL was always being built from scratch
        script 'addAdminUserToSQL' {
            PsDscRunAsCredential = $AdminCredential
            GetScript            = { return @{result = 'Adding Admin User to SQL sysadmin role for DB creation' } }
            TestScript           = { return $false }
            SetScript            = {                    
                #translate the configuration variables
                $thisSqlServer = $Using:ConfigurationData.RDSConfig.SqlServer
                $thisCredentialObjectSql = $Using:CredentialObjectSql
                $thisSqlPassword = $Using:ConfigurationData.RDSConfig.SqlPassword      
                $AdminUser = $Using:ConfigurationData.RDSConfig.AdminUser
                $thisDomainName = $Using:ConfigurationData.RDSConfig.DomainName

                $thisAdminUser = $thisDomainName + "\" + $AdminUser

                if (!((Get-SqlLogin -ServerInstance $thisSqlServer -LoginName $thisAdminUser -LoginType "WindowsUser" -Credential $thisCredentialObjectSql -errorAction SilentlyContinue).count -gt 0)) {
                    Add-SqlLogin -ServerInstance $thisSqlServer -LoginName $thisAdminUser -LoginType "WindowsUser" -GrantConnectSql -Enable -Credential $thisCredentialObjectSql
                    $svr = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $thisSqlServer
                    $svr.ConnectionContext.LoginSecure = $false
                    $svr.ConnectionContext.Login = "sqladmin"
                    $svr.ConnectionContext.Password = $thisSqlPassword
                    $svrole = $svr.Roles | where-object { $_.Name -eq 'sysadmin' }
                    $svrole.AddMember($thisAdminUser)     
                } 
            }
        }

        #TODO: Convert the condition checks to a Test Script
        script 'DeployInitialFarm' {
            PsDscRunAsCredential = $AdminCredential
            GetScript            = { return @{result = 'Initial Farm Creation Script' } }
            TestScript           = { return $false }
            SetScript            = {                    
                #translate the configuration variables
                $ThisBrokerHosts = $Using:ConfigurationData.RDSConfig.BrokerHosts
                $ThisSessionHosts = $Using:ConfigurationData.RDSConfig.SessionHosts
                $ThisWebHosts = $Using:ConfigurationData.RDSConfig.WebHosts

                #check for the Active Broker
                import-module remotedesktop  -global -Verbose:$false | Out-Null
                $ActiveManagementServer = $ThisBrokerHosts[0] 
                foreach ($Broker in $ThisBrokerHosts) {
                    $ThisBroker = $Broker 
                    if ((Get-RdServer -connectionBroker $ThisBroker -ErrorAction SilentlyContinue).count -gt 0) {
                        $activeManagementServer = $thisBroker
                    }
                }

                #If farm doesn't return data create the initial farm
                #TODO: Add a secondary check to make sure the active management server is running 
                if (!(Get-RDserver -ConnectionBroker $activeManagementServer -ErrorAction SilentlyContinue)) {
                    New-RDSessionDeployment -ConnectionBroker $ActiveManagementServer -SessionHost $ThisSessionHosts -WebAccessServer ($ThisWebHosts[0] )
                }
            }
        }


        script 'Configure_HA' {
            #DependsOn            = '[SqlLogin]RemoveBrokerGroup' 
            PsDscRunAsCredential = $AdminCredential
            GetScript            = { return @{result = 'Starting Broker HA configuration' } }
            TestScript           = { 
                #return $false 
                #translate the configuration variables
                $ThisBrokerHosts = $Using:ConfigurationData.RDSConfig.BrokerHosts
                
                #set the active management server
                import-module remotedesktop  -global -Verbose:$false | Out-Null -Verbose:$false | Out-Null
                $ActiveManagementServer = $ThisBrokerHosts[0] 
                foreach ($Broker in $ThisBrokerHosts) {
                    $ThisBroker = $Broker 
                    if ((Get-RdServer -connectionBroker $ThisBroker -ErrorAction SilentlyContinue).count -gt 0) {
                        $activeManagementServer = $thisBroker
                    }
                }

                if (!((Get-RDConnectionBrokerHighAvailability -ConnectionBroker $activeManagementServer -ErrorAction SilentlyContinue).ConnectionBroker.Count -gt 0)) {
                    return $false;
                }
                else {
                    return $true
                }            
            }
            SetScript            = {
                
                #translate the configuration variables
                $ThisBrokerHosts = $Using:ConfigurationData.RDSConfig.BrokerHosts
                $ThisDomainFqdn = $Using:ConfigurationData.RDSConfig.DomainFqdn
                $ThisBrokerGroupName = $Using:ConfigurationData.RDSConfig.BrokerGroupName                
                $ThisSqlServer = $Using:ConfigurationData.RDSConfig.SqlServer
                $ThisDomainName = $Using:ConfigurationData.RDSConfig.DomainName
                $thisCredentialObjectSql = $Using:CredentialObjectSql
                $thisSqlPassword = $Using:ConfigurationData.RDSConfig.sqlPassword
                $thisBrokerRecordName = $Using:ConfigurationData.RDSConfig.BrokerRecordName               

                $thisSqlClientShare = $Using:ConfigurationData.RDSConfig.sqlClientShare
                
                #set the active management server
                import-module remotedesktop  -global -Verbose:$false | Out-Null -Verbose:$false | Out-Null
                $ActiveManagementServer = $ThisBrokerHosts[0] 
                foreach ($Broker in $ThisBrokerHosts) {
                    $ThisBroker = $Broker 
                    if ((Get-RdServer -connectionBroker $ThisBroker -ErrorAction SilentlyContinue).count -gt 0) {
                        $activeManagementServer = $thisBroker
                    }
                }
                Write-Host "Active Management Server is $ActiveManagementServer"

                #If HA is unavailable (no connectionBrokerCount -gt 0 (assumes the firstBroker token has been set previously)) 
                #TODO: Add second condition to ensure that the broker is running
                if (!((Get-RDConnectionBrokerHighAvailability -ConnectionBroker $activeManagementServer -ErrorAction SilentlyContinue).ConnectionBroker.Count -gt 0)) {
                
                    #Create a new sql login for the broker group and assign sysadmin and dbcreator
                    #TODO: Consider pushing this to a log file for failure troubleshooting                
                    if (!((Get-SqlLogin -ServerInstance $thisSqlServer -LoginName "$thisDomainName\$thisBrokerGroupName" -LoginType "WindowsGroup" -Credential $thisCredentialObjectSql -errorAction SilentlyContinue).count -gt 0)) {
                        Add-SqlLogin -ServerInstance $thisSqlServer -LoginName "$thisDomainName\$thisBrokerGroupName" -LoginType "WindowsGroup" -GrantConnectSql -Enable -Credential $thisCredentialObjectSql
                        $svr = New-Object ('Microsoft.SqlServer.Management.Smo.Server') $thisSqlServer
                        $svr.ConnectionContext.LoginSecure = $false
                        $svr.ConnectionContext.Login = "sqladmin"
                        $svr.ConnectionContext.Password = "$thisSqlPassword" 
                        $svrole = $svr.Roles | where-object { $_.Name -eq 'sysadmin' -or $_.Name -eq 'dbcreator' }
                        $svrole.AddMember("$thisDomainName\$thisBrokerGroupName")  
                    }                     

                    #Force reboot the brokers - then install the SQL client. Allows for a delay to ensure all the services are back online before trying the HA config
                    foreach ($broker in $thisBrokerHosts) {  
                        Restart-Computer -ComputerName ($broker) -Wait -For PowerShell -Timeout 300 -Delay 60 -Force
                        start-sleep -s 60
                        #check to make sure the service comes back online for the active broker
                        if (($broker) -eq $thisFirstBroker) {
                            $thisCounter = 0
                            while ( ((get-service -name "Remote Desktop Management" -computer ($broker)).status -ne "Running") -and ($thisCounter -lt 10) ) {                                 
                                get-service -name "Remote Desktop Management" -computer ($broker ) | set-service -status running
                                start-sleep -s 60
                                $thisCounter += 1
                            }
                        }                         
                        
                        #re-attempt the sql-client install in case it failed during the terraform build
                        if (!(Get-Item -Path ('\\' + $broker + '\c$\temp'))) {
                            New-Item -Path ('\\' + $broker + '\c$\temp') -ItemType Directory
                        }   

                        #copy the client locally                         
                        $SourcefilePath = "\\" + $thisSqlServer + "\" + $ThisSqlClientShare + "\sqlncli.msi"
                        $folderPathDest = ('\\' + $broker + '\c$\temp')
                        Write-Host "Copying SQL client from $SourceFilePath to $folderPathDest"
                        Copy-Item -Path $SourcefilePath -Destination $folderPathDest -PassThru

                        #install the SQL native client
                        invoke-command -Computername ($broker) -ScriptBlock {                             
                            msiexec /i c:\temp\sqlncli.msi /qn IACCEPTSQLNCLILICENSETERMS=YES /log c:\temp\sqlclient_install.log                                              
                        }             
                        
                    }                                   

                    #Configure Broker HA                    
                    $databaseConnectionString = "DRIVER=SQL Server Native Client 11.0;SERVER=tcp:$thisSqlServer,1433;DATABASE=RDCB;APP=Remote Desktop Services Connection Broker;Trusted_Connection=Yes;"
                    Set-RDConnectionBrokerHighAvailability -ConnectionBroker $activeManagementServer -databaseConnectionString $databaseConnectionString -ClientAccessName ($thisBrokerRecordName + "." + $thisDomainFQDN)                                                       
                }  
            }
        }

        WaitForAny AtLeastOneGatewayHost
        {
            ResourceName      = '[script]AddGatewayToRDSFarm'
            NodeName          = $AllNodes.Where{ $_.Role -contains "Gateway" }.NodeName
            RetryIntervalSec  = 15
            RetryCount        = 30
            PsDscRunAsCredential = $AdminCredential
        }

                #add certificates - Using script resource since targeting server 2019 and using the thumbprint option
        #TODO: Check to see why the secondary gateway failed with error missing Module RDManagement while the first did not.  Is this installed as part of the initial deployment?
        #TODO: Consider moving this to the script host? (Does it need to wait for at least one Gateway to be added)
        script 'ConfigureCertificates' {
            DependsOn            = '[WaitForAny]AtLeastOneGatewayHost'
            PsDscRunAsCredential = $AdminCredential
            GetScript            = { return @{result = 'Configuring Certificate on the RDS Farm' } }
            TestScript           = { return $false }
            SetScript            = {                    
                
                #translate the configuration variables
                $thisThumbprint = $Using:ConfigurationData.RDSConfig.Thumbprint
                $roles = @("RDRedirector", "RDPublishing","RDGateway", "RDWebAccess")              
                $ThisBrokerHosts = $Using:ConfigurationData.RDSConfig.BrokerHosts
                
                import-module remotedesktop -Global -Verbose:$false | Out-Null
                #get the current active management server
                $ActiveManagementServer = $ThisBrokerHosts[0] 
                foreach ($Broker in $ThisBrokerHosts) {
                    $ThisBroker = $Broker 
                    if ((Get-RdServer -connectionBroker $ThisBroker -ErrorAction SilentlyContinue).count -gt 0) {
                        $ActiveManagementServer = $ThisBroker
                    }
                }
                
                Write-Host "Attempting Certificate Configuration with certificate Thumbprint $thisThumbprint using management server $activeManagementServer"
                
                foreach ($role in $roles) {
                    #if the current role returns not configured configure it
                    if ((Get-RDCertificate -ConnectionBroker $ActiveManagementServer -Role $role).Level -eq "NotConfigured") {
                        Write-Verbose "Installing Certificate for Role $role"
                        Set-RDCertificate -Role $role -Thumbprint $thisThumbprint -ConnectionBroker $ActiveManagementServer -force
                    }   #Else check to make sure the certificate is set to the thumbprint value and set it if it does not match.                 
                    elseif ( ( (Get-RDCertificate -ConnectionBroker $ActiveManagementServer -Role $role)[0].Thumbprint.toLower()) -ne $thisThumbprint.toLower()) {
                        Write-Verbose "Updating Certificate for Role $role"
                        Set-RDCertificate -Role $role -Thumbprint $thisThumbprint -ConnectionBroker $ActiveManagementServer -force                        
                    }
                }                 
            }
        }
    }

    #########################################################################
    # Configure additional broker hosts or new broker hosts
    #########################################################################
    Node $AllNodes.Where{ $_.Role -contains "Broker" }.NodeName
    {
        WaitForAll ScriptHost
        {
            ResourceName      = '[script]Configure_HA'
            NodeName          = $AllNodes.Where{ $_.Role -contains "Script" }.NodeName
            RetryIntervalSec  = 15
            RetryCount        = 30
            PsDscRunAsCredential = $AdminCredential
        }

        LocalConfigurationManager 
        {
            RebootNodeIfNeeded = $true
        }
        

        WindowsFeature 'Rsat-ADDS'
        {
            Name                 = 'RSAT-ADDS'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }
        
        WindowsFeature 'Rsat-RDS-Tools'
        {
            Name                 = 'RSAT-RDS-Tools'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }

        #Make sure the Feature is installed (Prevents OS version error)
        WindowsFeature 'RDS-Connection-Broker'
        {
            Name                 = 'RDS-Connection-Broker'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }    
        
        PendingReboot PostFeatureRebootCheck
        {
            Name = 'Broker-PostFeatureRebootCheck'
        }

        #Add the broker to the farm
        script 'AddBrokerToFarm' {
            DependsOn            = '[WaitForAll]ScriptHost'
            PsDscRunAsCredential = $AdminCredential
            GetScript            = { return @{result = 'Adding Broker to existing RDS farm' } }
            TestScript           = { return $false }
            SetScript            = {                    
                #translate the configuration variables
                $ThisBroker = $Using:ConfigurationData.RDSConfig.NodeName
                $ThisBrokerHosts = $Using:ConfigurationData.RDSConfig.BrokerHosts            
                $ThisSqlServer = $Using:ConfigurationData.RDSConfig.SqlServer
                $thisSqlClientShare = $Using:ConfigurationData.RDSConfig.sqlClientShare               

                import-module remotedesktop  -global -Verbose:$false | Out-Null
                #get the current active management server
                $ActiveManagementServer = $ThisBrokerHosts[0] 
                foreach ($Broker in $ThisBrokerHosts) {
                    $ThisBroker = $Broker 
                    if ((Get-RdServer -connectionBroker $ThisBroker -ErrorAction SilentlyContinue).count -gt 0) {
                        $ActiveManagementServer = $thisBroker
                    }
                }

                #if this broker isn't currently in the farm, then add it
                $addBrokerFlag = $true
                foreach ($configuredBroker in (Get-RDserver -Role "RDS-CONNECTION-BROKER" -ConnectionBroker $ActiveManagementServer)) {
                    if ( $configuredBroker.Server.ToLower() -eq ($ThisBroker).ToLower()) {
                        $addBrokerFlag = $false
                    }
                }                                       
                
                if ($addBrokerFlag) {
                    #re-attempt the sql-client install in case it failed during the terraform build and the initial build
                    if (!(Get-Item -Path 'c:\temp')) {
                        New-Item -Path 'c:\temp' -ItemType Directory
                    } 
                    $SourcefilePath = "\\" + $thisSqlServer + "\" + $thisSqlClientShare + "\sqlncli.msi"
                    $folderPathDest = "C:\temp\"
                    Copy-Item -Path $SourcefilePath -Destination $folderPathDest -PassThru

                    #install the SQL native client
                    msiexec /i c:\temp\sqlncli.msi /qn IACCEPTSQLNCLILICENSETERMS=YES /log c:\temp\sqlclient_install.log  

                    #force a purge on the tickets so the group membership will allow for login to the database 
                    klist -li 0x3e7 purge 

                    Write-Host "Adding Broker $ThisBroker to existing RD farm management server $ActiveManagementServer"
                    Add-RDServer -Server ($ThisBroker ) -Role "RDS-CONNECTION-BROKER" -ConnectionBroker $ActiveManagementServer
                }                        
            }
        }

        script 'ConfigureBrokersAsLicenseServers' {
            PsDscRunAsCredential = $AdminCredential
            GetScript            = { return @{result = 'License Server Configuration' } }
            TestScript           = { return $false }
            SetScript            = {                    
                #translate the configuration variables
                $ThisBrokerHosts = $Using:ConfigurationData.RDSConfig.BrokerHosts
                $ThisLicenseMode = $Using:ConfigurationData.RDSConfig.LicenseMode


                #check for the Active Broker
                import-module remotedesktop  -global -Verbose:$false | Out-Null
                $ActiveManagementServer = $ThisBrokerHosts[0] 
                foreach ($Broker in $ThisBrokerHosts) {
                    $ThisBroker = $Broker 
                    if ((Get-RdServer -connectionBroker $ThisBroker -ErrorAction SilentlyContinue).count -gt 0) {
                        $activeManagementServer = $thisBroker
                    }
                }

                #Set the license mode.  
                Set-RDLicenseConfiguration -LicenseServer $ThisBrokerHosts -Mode $ThisLicenseMode -ConnectionBroker $activeManagementServer -force
            }
        }
    }


    #########################################################################
    # Configure gateway hosts
    #########################################################################
    Node $AllNodes.Where{ $_.Role -contains "Gateway" }.NodeName
    {
        WaitForAll ScriptHost
        {
            ResourceName      = '[script]Configure_HA'
            NodeName          = $AllNodes.Where{ $_.Role -contains "Script" }.NodeName
            RetryIntervalSec  = 15
            RetryCount        = 30
            PsDscRunAsCredential = $AdminCredential
        }

        LocalConfigurationManager 
        {
            RebootNodeIfNeeded = $true
        }
        

        WindowsFeature 'Rsat-ADDS'
        {
            Name                 = 'RSAT-ADDS'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }
        
        WindowsFeature 'Rsat-RDS-Tools'
        {
            Name                 = 'RSAT-RDS-Tools'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }

        #Make sure the Feature is installed (Prevents OS version error)
        WindowsFeature 'RDS-Gateway'
        {
            Name                 = 'RDS-Gateway'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }  
        
        PendingReboot PostFeatureRebootCheck
        {
            Name = 'Gateway-PostFeatureRebootCheck'
        }

        script 'AddGatewayToRDSFarm' {
            DependsOn            = '[WaitForAll]ScriptHost'
            PsDscRunAsCredential = $AdminCredential
            GetScript            = { return @{result = 'Adding this Gateway Server to the RDS Farm' } }
            TestScript           = { 
                #return $false
                #translate the configuration variables
                $ThisBrokerHosts = $Using:ConfigurationData.RDSConfig.BrokerHosts
                $thisGateway = $Using:Node.NodeName
                    
                #set the active management server
                import-module remotedesktop  -global -Verbose:$false | Out-Null
                $ActiveManagementServer = $ThisBrokerHosts[0] 
                foreach ($Broker in $ThisBrokerHosts) {
                    $ThisBroker = $Broker 
                    if ((Get-RdServer -connectionBroker $ThisBroker -ErrorAction SilentlyContinue).count -gt 0) {
                        $activeManagementServer = $thisBroker
                    }
                }
                $addGatewayFlag = $false
                foreach ($configuredGateway in (Get-RDserver -Role "RDS-Gateway" -ConnectionBroker $ActiveManagementServer -ErrorAction SilentlyContinue)) {
                    if ( $configuredGateway.Server.ToLower() -eq ($thisGateway).ToLower()) {
                        $addGatewayFlag = $true
                    }
                } 

                return $addGatewayFlag   
            
            }
            SetScript            = {                    
                #translate the configuration variables
                $thisGateway = $Using:Node.NodeName
                $ThisBrokerHosts = $Using:ConfigurationData.RDSConfig.BrokerHosts
                $ThisDomainFqdn = $Using:ConfigurationData.RDSConfig.DomainFqdn 
                $thisGatewayRecord = $Using:ConfigurationData.RDSConfig.GatewayRecordName

                #$thisGateway = $thisGateway + "." + $thisDomainFQDN
                
                import-module remotedesktop  -global -Verbose:$false | Out-Null
                #get the current active management server
                $ActiveManagementServer = $ThisBrokerHosts[0] 
                foreach ($Broker in $ThisBrokerHosts) {
                    $ThisBroker = $Broker 
                    if ((Get-RdServer -connectionBroker $ThisBroker -ErrorAction SilentlyContinue).count -gt 0) {
                        $ActiveManagementServer = $thisBroker
                    }
                }               
            
                Write-Host "Adding $thisGateway as a Gateway to existing RD farm using management server $ActiveManagementServer"
                Add-RDServer -Server ($thisGateway ) -Role "RDS-Gateway" -ConnectionBroker $ActiveManagementServer -GatewayExternalFqdn ($thisGatewayRecord + "." + $thisDomainFQDN)
                
                Write-Verbose "Gateway Add Complete for $thisGateway"                      
            }
        }

        #Add gateway servers to the gateway farm
        script 'ConfigureGatewayFarm' {
            DependsOn            = '[script]AddGatewayToRDSFarm'
            PsDscRunAsCredential = $AdminCredential
            GetScript            = { return @{result = 'Adding this Gateway Server to the RDS Farm' } }
            TestScript           = { return $false }
            SetScript            = {                    
                #translate the configuration variables
                $ThisGatewayHosts = $Using:ConfigurationData.RDSConfig.gatewayHosts
                
                import-module remotedesktop  -global -Verbose:$false | Out-Null
                import-module RemoteDesktopServices -Verbose:$false | Out-Null
                foreach ($ThisGateway in $ThisGatewayHosts) {
                    

                    #check to see if the current gateway has already been added to the farm configuration on this host
                    $addflag = $true
                    foreach ($FarmGateway in (Get-ChildItem -Path "RDS:\GatewayServer\GatewayFarm\Servers")) {
                        if ($FarmGateway.name.toLower() -eq $ThisGateway.toLower()) {
                            $addFlag = $false
                            Write-Host "Gateway $ThisGateway already exists in the farm"
                        }
                    }
                    
                    #If this gateway is not in the local gateway farm, add it
                    if ($addFlag) {
                        New-Item -Path "RDS:\GatewayServer\GatewayFarm\Servers" -Name $ThisGateway.toLower() -ItemType "String"
                        Write-Host "Adding Gateway $ThisGateway to Gateway Farm"
                    }
                }                 
            }
        }

        #Configure Deployment to use the gateway farm
        script 'SetRDSGatewayConfiguration' {
            DependsOn            = '[script]AddGatewayToRDSFarm'
            PsDscRunAsCredential = $AdminCredential
            GetScript            = { return @{result = 'Configuring the RDS Farm to use the Gateway farm' } }
            TestScript           = { return $false }
            SetScript            = {                    
                #translate the configuration variables
                $ThisGatewayRecordName = $Using:ConfigurationData.RDSConfig.GatewayRecordName
                $ThisDomainFqdn = $Using:ConfigurationData.RDSConfig.DomainFqdn 
                $ThisBrokerHosts = $Using:ConfigurationData.RDSConfig.BrokerHosts

                $ThisGatewayFQDN = ($ThisGatewayRecordName + "." + $ThisDomainFQDN)
                
                import-module remotedesktop  -global -Verbose:$false | Out-Null
                #get the current active management server
                $ActiveManagementServer = $ThisBrokerHosts[0] 
                foreach ($Broker in $ThisBrokerHosts) {
                    $ThisBroker = $Broker 
                    if ((Get-RdServer -connectionBroker $ThisBroker -ErrorAction SilentlyContinue).count -gt 0) {
                        $ActiveManagementServer = $thisBroker
                    }
                }
                
                import-module remotedesktop  -global -Verbose:$false | Out-Null
                $GatewayConfig = Get-RDDeploymentGatewayConfiguration -ConnectionBroker $ActiveManagementServer
                #set a basic gateway configuration
                if ($GatewayConfig[0].GatewayMode -eq "DoNotUse") {
                    Write-Host "Setting the Gateway Configuration pointing to gateway $ThisGatewayFQDN"
                    Set-RDDeploymentGatewayConfiguration -ConnectionBroker $ActiveManagementServer -GatewayExternalFqdn ($ThisGatewayFQDN) -GatewayMode Custom -LogonMethod AllowUserToSelectDuringConnection -UseCachedCredentials $True -BypassLocal $True -Force
                }
                elseif (($GatewayConfig[0].GatewayExternalFQDN.toLower() -ne $ThisGatewayFQDN.toLower()) -or ($GatewayConfig[0].LogonMethod -ne "AllowUserToSelectDuringConnection")) {
                    Write-Host "Setting the Gateway Configuration pointing to gateway $ThisGatewayFQDN"
                    Set-RDDeploymentGatewayConfiguration -ConnectionBroker $ActiveManagementServer -GatewayExternalFqdn ($ThisGatewayFQDN) -GatewayMode Custom -LogonMethod AllowUserToSelectDuringConnection -UseCachedCredentials $True -BypassLocal $True -Force
                }               
            }
        }
    }

    #########################################################################
    # Configure Web hosts
    #########################################################################
    Node $AllNodes.Where{ $_.Role -contains "Web" }.NodeName
    {
        WaitForAll ScriptHost
        {
            ResourceName      = '[script]Configure_HA'
            NodeName          = $AllNodes.Where{ $_.Role -contains "Script" }.NodeName
            RetryIntervalSec  = 15
            RetryCount        = 30
            PsDscRunAsCredential = $AdminCredential
        }

        WindowsFeature 'Rsat-ADDS'
        {
            Name                 = 'RSAT-ADDS'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }
        
        WindowsFeature 'Rsat-RDS-Tools'
        {
            Name                 = 'RSAT-RDS-Tools'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }

        #Make sure the Feature is installed (Prevents OS version error)
        WindowsFeature 'RDS-Web-Access'
        {
            Name                 = 'RDS-Web-Access'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        } 

        PendingReboot PostFeatureRebootCheck
        {
            Name = 'Web-PostFeatureRebootCheck'
        }

        #adding Gateway to farm using a script resource since the xServer resources are inconsistent
        script 'AddWebToFarm' {
            DependsOn            = '[WaitForAll]ScriptHost'
            PsDscRunAsCredential = $AdminCredential
            GetScript            = { return @{result = 'Adding this Web Server to the RDS Farm' } }
            TestScript           = {
                #translate the configuration variables
                $ThisWeb = $Using:Node.NodeName
                $ThisBrokerHosts = $Using:ConfigurationData.RDSConfig.BrokerHosts
                
                import-module remotedesktop  -global -Verbose:$false | Out-Null
                #get the current active management server
                $ActiveManagementServer = $ThisBrokerHosts[0] 
                foreach ($Broker in $ThisBrokerHosts) {
                    $ThisBroker = $Broker 
                    if ((Get-RdServer -connectionBroker $ThisBroker -ErrorAction SilentlyContinue).count -gt 0) {
                        $ActiveManagementServer = $thisBroker
                    }
                }
 
                 $WebExistsFlag = $false
                 foreach ($configuredWeb in (Get-RDserver -Role "RDS-Web-Access" -ConnectionBroker $ActiveManagementServer -ErrorAction SilentlyContinue)) {
                     if ( $configuredWeb.Server.ToLower() -eq ($ThisWeb ).ToLower()) {
                        $WebExistsFlag = $true
                     }
                 }  
                
                return $WebExistsFlag }
            SetScript            = {                    
                #translate the configuration variables
                $ThisWeb = $Using:Node.NodeName
                $ThisBrokerHosts = $Using:ConfigurationData.RDSConfig.BrokerHosts
                
                import-module remotedesktop  -global -Verbose:$false | Out-Null
                #get the current active management server
                $ActiveManagementServer = $ThisBrokerHosts[0] 
                foreach ($Broker in $ThisBrokerHosts) {
                    $ThisBroker = $Broker 
                    if ((Get-RdServer -connectionBroker $ThisBroker -ErrorAction SilentlyContinue).count -gt 0) {
                        $ActiveManagementServer = $thisBroker
                    }
                }

                Write-Host "Adding Web host $ThisWeb to existing RD farm"
                Add-RDServer -Server $ThisWeb  -Role "RDS-Web-Access" -ConnectionBroker $ActiveManagementServer 
    
                Write-Verbose "Web Add Complete for $ThisWeb"                      
            }
        }

        #configure the machine keys for all the websites per the documentation
        script 'UpdateMachineKeys' {
            DependsOn            = '[WindowsFeature]RDS-Web-Access' 
            PsDscRunAsCredential = $AdminCredential
            GetScript            = { return @{result = 'Checking RDWeb App Settings' } }
            TestScript           = { return $false }
            SetScript            = {                    
                #translate the configuration variables
                $thisWeb = $Using:Node.NodeName
                $thisDecryption = $Using:ConfigurationData.RDSConfig.Decryption
                $thisValidation = $Using:ConfigurationData.RDSConfig.Validation
                $thisDecryptionKey = $Using:ConfigurationData.RDSConfig.DecryptionKey
                $thisValidationKey = $Using:ConfigurationData.RDSConfig.ValidationKey

                $sites = @("RDWeb", "RDWeb/Feed", "RDWeb/FeedLogin", "RDWeb/Pages")

                foreach ($site in $sites) {
                    if (!((Get-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/Default Web Site/$site"  -filter "system.web/machineKey" -name "decryption").Value -eq $thisDecryption )) {
                        Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/Default Web Site/$site"  -filter "system.web/machineKey" -name "decryption" -value $thisDecryption
                        Write-Verbose "Updating the decryption value on site $site for $thisWeb"
                    }

                    if (!((Get-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/Default Web Site/$site"  -filter "system.web/machineKey" -name "decryptionKey").Value -eq $thisDecryptionKey )) {
                        Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/Default Web Site/$site"  -filter "system.web/machineKey" -name "decryptionKey" -value $thisDecryptionKey
                        Write-Verbose "Updating the decryptionKey value on site $site for $thisWeb"
                    }

                    if (!((Get-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/Default Web Site/$site"  -filter "system.web/machineKey" -name "validation").Value -eq $thisValidation )) {
                        Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/Default Web Site/$site"  -filter "system.web/machineKey" -name "validation" -value $thisValidation
                        Write-Verbose "Updating the validation value on site $site for $thisWeb"
                    }

                    if (!((Get-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/Default Web Site/$site"  -filter "system.web/machineKey" -name "validationKey").Value -eq $thisValidationKey )) {
                        Set-WebConfigurationProperty -pspath "MACHINE/WEBROOT/APPHOST/Default Web Site/$site"  -filter "system.web/machineKey" -name "validationKey" -value $thisValidationKey
                        Write-Verbose "Updating the validationKey value on site $site for $thisWeb"
                    }
                }                        
            }
        }
    }

    #########################################################################
    # Configure Session hosts
    #########################################################################
    Node $AllNodes.Where{ $_.Role -contains "Session" }.NodeName
    {
        WaitForAll ScriptHost
        {
            ResourceName      = '[script]Configure_HA'
            NodeName          = $AllNodes.Where{ $_.Role -contains "Script" }.NodeName
            RetryIntervalSec  = 15
            RetryCount        = 30
            PsDscRunAsCredential = $AdminCredential
        }

        WindowsFeature 'Rsat-ADDS'
        {
            Name                 = 'RSAT-ADDS'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }
        
        WindowsFeature 'Rsat-RDS-Tools'
        {
            Name                 = 'RSAT-RDS-Tools'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        }

        WindowsFeature 'RDS-RD-Server'
        {
            Name                 = 'RDS-RD-Server'
            Ensure               = 'Present'
            IncludeAllSubFeature = $true 
        } 

        PendingReboot 'PostFeatureRebootCheck'
        {
            Name = 'Session-PostFeatureRebootCheck'
        }

        #Add this session host to the Farm if not previously added.  
        script 'AddSessionToFarm' {
            DependsOn            = '[WaitForAll]ScriptHost'
            PsDscRunAsCredential = $AdminCredential
            GetScript            = { return @{result = 'Adding this Session Server to the RDS Farm' } }
            TestScript           = { 
                #translate the configuration variables
                $ThisSession = $Using:Node.NodeName
                $ThisBrokerHosts = $Using:ConfigurationData.RDSConfig.BrokerHosts
                
                import-module remotedesktop  -global -Verbose:$false | Out-Null
                #get the current active management server
                $ActiveManagementServer = $ThisBrokerHosts[0] 
                foreach ($Broker in $ThisBrokerHosts) {
                    $ThisBroker = $Broker 
                    if ((Get-RdServer -connectionBroker $ThisBroker -ErrorAction SilentlyContinue).count -gt 0) {
                        $ActiveManagementServer = $thisBroker
                    }
                }

                #Check to see if session host has already been added
                $SessionFlagExists = $false
                foreach ($configuredSession in (Get-RDserver -Role "RDS-RD-Server" -ConnectionBroker $ActiveManagementServer -ErrorAction SilentlyContinue )) {
                    if ( $configuredSession.Server.ToLower() -eq ($thisSession ).ToLower()) {
                        $SessionFlagExists = $true
                    }
                }   
                
                return $SessionFlagExists }
            SetScript            = {                    
               
                #translate the configuration variables
                $ThisSession = $Using:Node.NodeName
                $ThisBrokerHosts = $Using:ConfigurationData.RDSConfig.BrokerHosts

                import-module remotedesktop  -global -Verbose:$false | Out-Null
                #get the current active management server
                $ActiveManagementServer = $ThisBrokerHosts[0] 
                foreach ($Broker in $ThisBrokerHosts) {
                    $ThisBroker = $Broker 
                    if ((Get-RdServer -connectionBroker $ThisBroker -ErrorAction SilentlyContinue).count -gt 0) {
                        $ActiveManagementServer = $thisBroker
                    }
                }                                   
                

                Write-Host "Adding Session Host to existing RD farm"
                Add-RDServer -Server ($thisSession ) -Role "RDS-RD-Server" -ConnectionBroker $ActiveManagementServer
                Write-Host "Session Host Add Complete for $thisSession"                
                                 
            }
        }

        #Validate the Collection associated with this session host has been created and create it if not
        #assumes that session hosts can only be assigned to one collection 
        #This does not account for the case when a previously created session collection will need to be removed.  A separate script resource would be required to accomplish this?
        script 'CreateInitialSessionCollection' {
            DependsOn            = '[script]AddSessionToFarm'
            PsDscRunAsCredential = $AdminCredential
            GetScript            = { return @{result = 'Adding this Session Collection to the RDS Farm' } }
            TestScript           = { return $false }
            SetScript            = {                  
                
                #translate the configuration variables
                $ThisSessionHost = $Using:Node.NodeName
                $ThisBrokerHosts = $Using:ConfigurationData.RDSConfig.BrokerHosts
                $thisSessionCollections = $Using:ConfigurationData.RDSConfig.sessionCollections
                                
                import-module remotedesktop  -global -Verbose:$false | Out-Null
                #get the current active management server
                $ActiveManagementServer = $ThisBrokerHosts[0] 
                foreach ($Broker in $ThisBrokerHosts) {
                    $ThisBroker = $Broker 
                    if ((Get-RdServer -connectionBroker $ThisBroker -ErrorAction SilentlyContinue).count -gt 0) {
                        $ActiveManagementServer = $thisBroker
                    }
                }   

                #lookup the session host in the session collections
                foreach ($collection in $thisSessionCollections) {
                    foreach ($sessionHost in $collection.SessionHosts) {
                        if ($sessionHost.toLower() -eq $thisSessionHost.toLower()) {
                            #If a collection -> Session host match is found check to see if the collection is known to the broker
                            if (!((Get-RDSessionCollection -CollectionName $collection.Name -ConnectionBroker $ActiveManagementServer -errorAction SilentlyContinue).Count -gt 0)) {
                                Write-Host ("Creating new collection " + $collection.Name)
                                New-RDSessionCollection -CollectionName $collection.Name -SessionHost $thisSessionHost -CollectionDescription $collection.Description -ConnectionBroker $ActiveManagementServer
                            }
                            else {
                                Write-Host ("Collection " + $collection.Name + "already exists in the farm")
                            }
                        }
                    }
                }                                                           
            }
        }

        script 'AddSessionToCollection' {
            DependsOn            = '[script]CreateInitialSessionCollection'
            PsDscRunAsCredential = $AdminCredential
            GetScript            = { return @{result = 'Adding this Session Server to the RDS Farm' } }
            TestScript           = { return $false }
            SetScript            = {                    
                #translate the configuration variables
                $ThisSessionHost = $Using:Node.NodeName
                $ThisBrokerHosts = $Using:ConfigurationData.RDSConfig.BrokerHosts
                $thisSessionCollections = $Using:ConfigurationData.RDSConfig.sessionCollections

                import-module remotedesktop  -global -Verbose:$false | Out-Null
                #get the current active management server
                $ActiveManagementServer = $ThisBrokerHosts[0] 
                foreach ($Broker in $ThisBrokerHosts) {
                    $ThisBroker = $Broker 
                    if ((Get-RdServer -connectionBroker $ThisBroker -ErrorAction SilentlyContinue).count -gt 0) {
                        $ActiveManagementServer = $thisBroker
                    }
                }   

                #lookup the session host to collection mapping in the collections input
                foreach ($collection in $thisSessionCollections) {
                    foreach ($sessionHost in $collection.SessionHosts) {
                        if ($sessionHost.toLower() -eq $thisSessionHost.toLower()) {

                            $addHost = $true
                            foreach ($collectionHost in (Get-RDSessionHost -CollectionName $collection.Name -ConnectionBroker $ActiveManagementServer -errorAction SilentlyContinue).SessionHost) {
                                #if the host is found turn off the install flag
                                if ($collectionHost.toLower -eq $thisSessionHost.toLower() ) {
                                    $addHost = $false
                                }
                            }

                            #Add the host to the collection if the install flag is true
                            if ($addHost) {
                                Add-RDSessionHost -CollectionName $collection.Name -ConnectionBroker $ActiveManagementServer -SessionHost $ThisSessionHost -errorAction SilentlyContinue
                                Write-Host ("Adding Session Host " + $ThisSessionHost + " to collection " + $collection.Name)
                            }
                            else {
                                Write-Host ("Session Host " + $ThisSessionHost + " already exists in collection " + $collection.Name)
                            }
                        }
                    }
                }                                            
            }
        }
    }
}

$config_data = @{
    #############################
    # Inject variables for all nodes
    #############################
    ${full_config}

    RDSConfig = @{
        #define role group names
        BrokerGroupName       = "${broker_group_name}"
        SessionGroupName      = "${session_group_name}"
        GatewayGroupName      = "${gateway_group_name}"
        webGroupName          = "${web_group_name}"
        #define hosts for each role type
        BrokerHosts           = @(${broker_hosts})
        SessionHosts          = @(${session_hosts})
        GatewayHosts          = @(${gateway_hosts})
        WebHosts              = @(${web_hosts})

        GroupBrokerHosts      = @(${group_broker_hosts})
        GroupSessionHosts     = @(${group_session_hosts})
        GroupGatewayHosts     = @(${group_gateway_hosts})
        GroupWebHosts         = @(${group_web_hosts})
        
        #define the LoadBalancer configuration details
        BrokerRecordName      = "${broker_record_name}"
        GatewayRecordName     = "${gateway_record_name}"
        WebRecordName         = "${web_record_name}"
        BrokerLbIpAddress     = "${broker_lb_ip_address}"
        GatewayLbIpAddress    = "${gateway_lb_ip_address}"
        WebLbIpAddress        = "${web_lb_ip_address}"
        #define the domain details
        DomainName            = "${domain_name}"
        DomainFqdn            = "${domain_fqdn}"
        #define the SQL details
        SqlServer             = "${sql_server}"
        SqlServerInstance     = "${sql_server_instance}"
        SqlClientShare        = "sqlclient" 
        #Set the license mode
        LicenseMode           = "${license_mode}"

        #define the secrets - TODO: move this to a more secure implementation
        AdminUser             = "${admin_user}"
        sqladmin              = "${sql_admin}"
        sqlPassword           = "${sql_password}" 
        Thumbprint            = "${thumbprint}"
        ValidationKey         = "${validation_key}"
        DecryptionKey         = "${decryption_key}"
        Decryption            = "AES"
        Validation            = "HMACSHA256"
        sessionCollections    = @(
            [PSCustomObject]@{
                name         = "${collection_name}"
                Description  = "${collection_description}"
                sessionHosts = @(${session_hosts})
            }
        )                        
    }
} 

rdsHAConfig -ConfigurationData $config_data


#to run, . source the file . ./filename
#apply using  Start-dscConfiguration -Path ./rdsHAConfig -Force