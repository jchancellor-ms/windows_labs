$disks = Get-Disk | Where-Object IsBoot -eq $false | Where-Object partitionstyle -eq 'RAW'  

#$letters = 70..89 | ForEach-Object { [char]$_ }
$count = 0
#$labels = "DATA","LOGS"
#todo - turn this into a template file that has the labels as a variable so it can handle varying quantities of data disks
foreach ($disk in $disks) {
    #$driveLetter = $letters[$count].ToString()
    $disk | 
    Initialize-Disk -PartitionStyle GPT -PassThru 
    #|
    #New-Partition -UseMaximumSize -DriveLetter $driveLetter |
    #Format-Volume -FileSystem NTFS -NewFileSystemLabel $labels[$count] -Confirm:$false -Force
$count++
}

#create a share for the sql client msi
#configure share
New-Item -Path 'c:\sqlclient' -ItemType Directory
New-SmbShare -Name sqlclient -Description "SQL client" -Path c:\sqlclient 
Grant-SmbShareAccess -Name sqlclient -accountName Everyone -AccessRight Read -Force

#copy sql client msi to share location
$SourcefilePath = “c:\SQLServerFull\1033_ENU_LP\x64\Setup\x64\sqlncli.msi”
$folderPathDest = “C:\sqlclient\”
Copy-Item -Path $SourcefilePath -Destination $folderPathDest -PassThru

