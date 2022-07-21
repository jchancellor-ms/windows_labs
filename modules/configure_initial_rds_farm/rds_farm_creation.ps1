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
New-ADServiceAccount ${gmsa_account_name} -DNSHostName "${gmsa_account_name}.${active_directory_domain}" -PrincipalsAllowedToRetrieveManagedPassword ${broker_group_name} -ManagedPasswordIntervalInDays 1 -ServicePrincipalNames http/${gmsa_account_name}.${active_directory_domain} 

#register the a-record for the broker load-balancer
Add-DnsServerResourceRecordA -Name ${broker_record_name} -ZoneName "${active_directory_domain}" -AllowUpdateAny -IPv4Address "${broker_ip}" -TimeToLive 01:00:00 -computerName "${active_directory_domain}"
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
Add-SqlLogin -ServerInstance ql-westus2-t6 -LoginName "${active_directory_netbios_name}\${gmsa_account_name}$" -LoginType "WindowsUser" -GrantConnectSql -Enable -Credential $credentialObjectSql
Add-SqlLogin -ServerInstance ql-westus2-t6 -LoginName "${active_directory_netbios_name}\${script_vm_name}$" -LoginType "WindowsUser" -GrantConnectSql -Enable -Credential $credentialObjectSql
Add-SqlLogin -ServerInstance ql-westus2-t6 -LoginName "${active_directory_netbios_name}\${broker_group_name}" -LoginType "WindowsGroup" -GrantConnectSql -Enable -Credential $credentialObjectSql

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
    New-RDSessionDeployment -connectionBroker ${broker_vm_name}.${active_directory_domain}  -WebAccessServer ${gateway_vm_name}.${active_directory_domain}  -SessionHost ${session_vm_name}.${active_directory_domain} 
    Start-Sleep -Seconds 180
    #restart the session-host to make sure it comes up cleanly after role deployment
    restart-computer -computerName ${session_vm_name}.${active_directory_domain}  -Wait -For Powershell -Timeout 180 -Delay 5 
} -Credential $adCredentialObject | Wait-Job
Write-Host $config_initial_rds.ChildJobs[0].Error

#create some initial content
New-RDSessionCollection -collectionName TestCollection -sessionHost ${session_vm_name} -connectionBroker ${broker_vm_name}
New-RDRemoteapp -Alias Wordpad -DisplayName WordPad -FilePath "C:\Program Files\Windows NT\Accessories\wordpad.exe" -ShowInWebAccess 1 -CollectionName "TestCollection" -ConnectionBroker ${broker_vm_name}

##################################################################################
# Configure Farm Redundancy
##################################################################################
$databaseConnectionString = "DRIVER=SQL Server Native Client 11.0;SERVER=tcp:${sql_vm_name},1433;DATABASE=RDCB;APP=Remote Desktop Services Connection Broker;Trusted_Connection=Yes;"
Set-RDConnectionBrokerHighAvailability -ConnectionBroker ${broker_vm_name}.${active_directory_domain} -databaseConnectionString $databaseConnectionString -ClientAccessName ${broker_record_name}.${active_directory_name}




#configure share
#New-Item -Path 'f:\shares\upd' -ItemType Directory
#New-SmbShare -Name UPD -Description "User Profile Disks" -Path f:\Shares\UPD 
#grant access to the session hosts group
#Grant-SmbShareAccess -Name UPD -accountName "${active_directory_netbios_name}\${session_host_group}" -AccessRight Full -Force