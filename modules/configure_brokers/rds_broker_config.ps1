

#install the AD tools powershell
Install-WindowsFeature RSAT-AD-Powershell

Add-ADGroupMember "${broker_group_name}" -members "${vm_name}$"
Add-LocalGroupMember -Group "Administrators" "${active_directory_netbios_name}\${gmsa_account_name}$"

#copy and install the sql native client from sql server
New-Item -Path 'c:\temp' -ItemType Directory #TODO - update this to validate whether directory exists prior to creation
$SourcefilePath = “\\${sql_vm_name}\sqlclient\sqlncli.msi”
$folderPathDest = “C:\temp\”
Copy-Item -Path $SourcefilePath -Destination $folderPathDest -PassThru

#install the SQL native client
c:\temp\sqlncli.msi /quiet

#Create windows firewall rule allowing SQL 1433 and 1434 
New-NetFirewallRule -DisplayName "Allow SQL outbound-Default Instance" -Direction Outbound -LocalPort 1433 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "Allow SQL outbound-Browser Service" -Direction Outbound -LocalPort 1434 -Protocol UDP -Action Allow

#configure Broker HA if this is the first time through
if (!(Get-RDConnectionBrokerHighAvailability -ConnectionBroker ${first_broker_vm}.${active_directory_domain})) {
    $databaseConnectionString = "DRIVER=SQL Server Native Client 11.0;SERVER=tcp:${sql_vm_name},1433;DATABASE=RDCB;APP=Remote Desktop Services Connection Broker;Trusted_Connection=Yes;"
    Set-RDConnectionBrokerHighAvailability -ConnectionBroker ${first_broker_vm}.${active_directory_domain} -databaseConnectionString $databaseConnectionString -ClientAccessName ${broker_record_name}.${active_directory_domain}

}


#install the broker role
import-module remotedesktop

#check to see if server is already assigned the broker role and add it if not ()
if ((get-RDServer | where-object {$_.Server -like "*${vm_name}*"}).count -eq 0) {
    Add-RDServer -Server ${vm_name} -Role "RDS-CONNECTION-BROKER" -ConnectionBroker ${broker_record_name}.${active_directory_domain}
}

#Create local rights assignments for the GMSA account to mimic NETWORK Service rights
#Since this is a test lab, using a function in public repo - https://raw.githubusercontent.com/blakedrumm/SCOM-Scripts-and-SQL/master/Powershell/General%20Functions/Set-UserRights.ps1
#If using this in production setting consider using a group policy or other mechanism to effect this config
invoke-RestMethod -URI 'https://raw.githubusercontent.com/blakedrumm/SCOM-Scripts-and-SQL/master/Powershell/General%20Functions/Set-UserRights.ps1' -OutFile .\set-userrights.ps1

#set the updated rights on the gmsa account locally
.\Set-UserRights.ps1 -AddRight -Username "${active_directory_netbios_name}\${gmsa_account_name}$" -UserRight SeIncreaseQuotaPrivilege
.\Set-UserRights.ps1 -AddRight -Username "${active_directory_netbios_name}\${gmsa_account_name}$" -UserRight SeAuditPrivilege
.\Set-UserRights.ps1 -AddRight -Username "${active_directory_netbios_name}\${gmsa_account_name}$" -UserRight SeServiceLogonRight
.\Set-UserRights.ps1 -AddRight -Username "${active_directory_netbios_name}\${gmsa_account_name}$" -UserRight SeAssignPrimaryTokenPrivilege
.\Set-UserRights.ps1 -AddRight -Username "${active_directory_netbios_name}\${gmsa_account_name}$" -UserRight SeImpersonatePrivilege

#update the broker services to use the gmsa account
#update the connection broker service
$Svc_tssdis = Get-WmiObject win32_service -filter "name='tssdis'"
$Svc_tssdis.Change($Null, $Null, $Null, $Null, $Null, $Null, "${active_directory_netbios_name}\${gmsa_account_name}$", "")

Stop-Service -Name 'tssdis'
Start-Service -Name 'tssdis'

#update the rds management service
$Svc_rdms = Get-WmiObject win32_service -filter "name='rdms'"
$Svc_rdms.Change($Null, $Null, $Null, $Null, $Null, $Null, "${active_directory_netbios_name}\${gmsa_account_name}$", "")

Stop-Service -Name 'rdms'
Start-Service -Name 'rdms'

#update the RD publishing service (RemoteApp and desktop connection management)
$Svc_tscpubrpc = Get-WmiObject win32_service -filter "name='tscpubrpc'"
$Svc_tscpubrpc.Change($Null, $Null, $Null, $Null, $Null, $Null, "${active_directory_netbios_name}\${gmsa_account_name}$", "")

Stop-Service -Name 'tscpubrpc'
Start-Service -Name 'tscpubrpc'


#Configure the connection string and force the restore database connection in the event this is the second broker. (TODO:validate if this is needed)  
$databaseConnectionString = "DRIVER=SQL Server Native Client 11.0;SERVER=tcp:${sql_vm_name},1433;DATABASE=RDCB;APP=Remote Desktop Services Connection Broker;Trusted_Connection=Yes;"
Set-RDDatabaseConnectionString -ConnectionBroker ${broker_record_name}.${active_directory_domain} -DatabaseConnectionString $databaseConnectionString -RestoreDatabaseConnection -RestoreDBConnectionOnAllBrokers

#add connection broker to load-balancer after completion