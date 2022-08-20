Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name ActiveDirectoryDsc -Force -AllowClobber
Install-Module -Name DnsServerDsc -Force -AllowClobber
Install-Module -Name SqlServerDsc -Force -AllowClobber
Install-Module -Name SecurityPolicyDsc -Force -AllowClobber
Install-Module -Name ComputerManagementDsc -Force -AllowClobber
Install-Module -Name WebAdministrationDsc -Force -AllowClobber
Install-Module -Name xRemoteDesktopSessionHost -Force -AllowClobber
Install-Module -Name SqlServer -Force -AllowClobber

New-NetFirewallRule -DisplayName "Allow Web Inbound" -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow
New-NetFirewallRule -DisplayName "Allow RDP UDP Inbound" -Direction Inbound -LocalPort 3391 -Protocol UDP -Action Allow