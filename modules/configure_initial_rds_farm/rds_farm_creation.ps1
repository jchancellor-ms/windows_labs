##################################################################################
# configure the domain objects (gmsa, dns, groups)
##################################################################################

$secureString = "${aduser_password}" | ConvertTo-SecureString -AsPlainText -Force 
$adCredentialObject = New-Object System.Management.Automation.PSCredential -ArgumentList "${active_directory_netbios_name}\azureuser" , $secureString

$config_domain = Start-Job -ScriptBlock {

#install the RSAT modules 
Install-WindowsFeature  -Name RSAT-ADDS
Install-WindowsFeature -Name RSAT-DNS-Server    

#add the initial KDS root key (back dated so it is available immediately - not recommended for production)
Add-KdsRootKey -EffectiveTime ((get-date).addhours(-10))
#create a new security group for the broker
New-ADGroup -Name ${broker_group_name} -GroupCategory Security -GroupScope Global
New-ADGroup -Name ${session_group_name} -GroupCategory Security -GroupScope Global
#create the gmsa account
New-ADServiceAccount ${gmsa_account_name} -DNSHostName "${gmsa_account_name}.${active_directory_domain_fqdn}" -PrincipalsAllowedToRetrieveManagedPassword ${broker_group_name} -ManagedPasswordIntervalInDays 1 -ServicePrincipalNames http/${gmsa_account_name}.${active_directory_domain_fqdn} 

#register the a-record for the broker load-balancer
Add-DnsServerResourceRecordA -Name ${broker_record_name} -ZoneName "${active_directory_domain_fqdn}" -AllowUpdateAny -IPv4Address "${broker_ip}" -TimeToLive 01:00:00 -computerName "${active_directory_domain_fqdn}"
} -Credential $adCredentialObject | Wait-Job

#write out any errors for troubleshooting
Write-Host $config_domain.ChildJobs[0].Error

##################################################################################
# Configure the SQL permissions for the gmsa and the script VM
##################################################################################
#create a credential for the sqladmin account
$secureString = "${sqladmin_password}" | ConvertTo-SecureString -AsPlainText -Force 
$credentialObjectSql = New-Object System.Management.Automation.PSCredential -ArgumentList "sqladmin" , $secureString

#create the local machine credential object 

#Install the SQL powershell modules from the gallery
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module sqlserver -Confirm:$False -Force -AllowClobber
Invoke-Sqlcmd | Out-Null #hack to get sql modules in case the install-module fails to download properly

#add the logins for the script host and the gmsa account and the connection brokers group temporarily
Add-SqlLogin -ServerInstance ${sql_vm_name} -LoginName "${active_directory_netbios_name}\${gmsa_account_name}$" -LoginType "WindowsUser" -GrantConnectSql -Enable -Credential $credentialObjectSql
Add-SqlLogin -ServerInstance ${sql_vm_name} -LoginName "${active_directory_netbios_name}\${script_vm_name}$" -LoginType "WindowsUser" -GrantConnectSql -Enable -Credential $credentialObjectSql
Add-SqlLogin -ServerInstance ${sql_vm_name} -LoginName "${active_directory_netbios_name}\${broker_group_name}" -LoginType "WindowsGroup" -GrantConnectSql -Enable -Credential $credentialObjectSql

#add permissions to the logins for sysadmin and dbcreator
$svr = New-Object ('Microsoft.SqlServer.Management.Smo.Server') ${sql_vm_name}
$svr.ConnectionContext.LoginSecure = $false
$svr.ConnectionContext.Login = "sqladmin"
$svr.ConnectionContext.Password = "${sqladmin_password}" 
$svrole = $svr.Roles | where-object {$_.Name -eq 'sysadmin' -or $_.Name -eq 'dbcreator'}
$svrole.AddMember("${active_directory_netbios_name}\${gmsa_account_name}$")
$svrole.AddMember("${active_directory_netbios_name}\${script_vm_name}$")
$svrole.AddMember("${active_directory_netbios_name}\${broker_group_name}")


##################################################################################
# Configure the Initial farm
##################################################################################
#Import the remote desktop powershell
import-module remotedesktop

#Run the initial farm configuration command
$config_initial_rds = Start-Job -ScriptBlock {
    New-RDSessionDeployment -connectionBroker ${broker_vm_name}.${active_directory_domain_fqdn}  -WebAccessServer ${gateway_vm_name}.${active_directory_domain_fqdn}  -SessionHost ${session_vm_name}.${active_directory_domain_fqdn} 
    Start-Sleep -Seconds 180
    #restart the session-host to make sure it comes up cleanly after role deployment
    restart-computer -computerName ${session_vm_name}.${active_directory_domain_fqdn}  -Wait -For Powershell -Timeout 180 -Delay 5 
} -Credential $adCredentialObject | Wait-Job
Write-Host $config_initial_rds.ChildJobs[0].Error

#create some initial content
New-RDSessionCollection -collectionName TestCollection -sessionHost ${session_vm_name}.${active_directory_domain_fqdn} -connectionBroker ${broker_vm_name}.${active_directory_domain_fqdn}
New-RDRemoteapp -Alias Wordpad -DisplayName WordPad -FilePath "C:\Program Files\Windows NT\Accessories\wordpad.exe" -ShowInWebAccess 1 -CollectionName "TestCollection" -ConnectionBroker ${broker_vm_name}.${active_directory_domain_fqdn}

