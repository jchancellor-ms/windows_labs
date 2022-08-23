[DSCLocalConfigurationManager()]
Configuration lcmConfig
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $NodeName
    )

    Node $NodeName
    {
        Settings
        {
            RefreshMode = 'Push'
            ActionAfterReboot = "ContinueConfiguration"
            RebootNodeIfNeeded = $true
        }
    }
}


$hosts = @('rb-westus2-ac-1','rb-westus2-ac-2','rg-westus2-ac-1','rg-westus2-ac-2','rw-westus2-ac-1','rw-westus2-ac-2','rs-westus2-ac-1','rs-westus2-ac-2','sc-westus2-ac-1')
$pass = ConvertTo-SecureString "A44kW1Yuz8Y4u5pzg97t" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ("azuretestzone\azureuser", $pass)


Write-Host "Creating mofs"
foreach($hostname in $hosts){
    lcmConfig -NodeName $hostname -OutputPath .\lcmConfig
    $cim = New-CimSession -ComputerName $hostname -Credential $cred
    Set-DscLocalConfigurationManager -CimSession $cim -Path .\lcmConfig -Verbose
    Get-DscLocalConfigurationManager -CimSession $cim
}


