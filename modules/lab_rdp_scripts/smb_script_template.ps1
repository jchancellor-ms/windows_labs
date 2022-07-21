#restart the dc
#Restart-Computer -ComputerName ${dc_vm_name}

#wait for the dc to come back online
#Start-Sleep -Seconds 180

#initialize extra drives
$disks = Get-Disk | Where-Object IsBoot -eq $false | Where-Object partitionstyle -eq 'RAW'  

$letters = 70..89 | ForEach-Object { [char]$_ }
$count = 0
$labels = "SHARES"
#todo - turn this into a template file that has the labels as a variable so it can handle varying quantities of data disks
foreach ($disk in $disks) {
    $driveLetter = $letters[$count].ToString()
    $disk | Initialize-Disk -PartitionStyle GPT -PassThru |
    New-Partition -UseMaximumSize -DriveLetter $driveLetter |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel $labels[$count] -Confirm:$false -Force
$count++
}



