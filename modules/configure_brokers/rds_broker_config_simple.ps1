#copy and install the sql native client from sql server
New-Item -Path 'c:\temp' -ItemType Directory #TODO - update this to validate whether directory exists prior to creation
$SourcefilePath = “\\${sql_vm_name}\sqlclient\sqlncli.msi”
$folderPathDest = “C:\temp\”
Copy-Item -Path $SourcefilePath -Destination $folderPathDest -PassThru

#install the SQL native client
msiexec /i c:\temp\sqlncli.msi /qn IACCEPTSQLNCLILICENSETERMS=YES /log c:\temp\sqlclient_install.log

#Create windows firewall rule allowing SQL 1433 and 1434 
New-NetFirewallRule -DisplayName "Allow SQL outbound-Default Instance" -Direction Outbound -LocalPort 1433 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "Allow SQL outbound-Browser Service" -Direction Outbound -LocalPort 1434 -Protocol UDP -Action Allow

Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name ActiveDirectoryDsc -Force -AllowClobber
Install-Module -Name DnsServerDsc -Force -AllowClobber
Install-Module -Name SqlServerDsc -Force -AllowClobber
Install-Module -Name SecurityPolicyDsc -Force -AllowClobber
Install-Module -Name ComputerManagementDsc -Force -AllowClobber
Install-Module -Name WebAdministrationDsc -Force -AllowClobber
Install-Module -Name xRemoteDesktopSessionHost -Force -AllowClobber
Install-Module -Name SqlServer -Force -AllowClobber