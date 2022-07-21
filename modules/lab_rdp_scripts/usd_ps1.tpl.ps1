New-Item -Path 'g:\shares\upd' -ItemType Directory
New-SmbShare -Name UPD -Description "User Profile Disks" -Path G:\Shares\UPD -Force
Grant-SmbShareAccess -Name UPD -accountName ${sessionhost} -AccessRight Full -Force


oHw7Tcan4eM0wt4PNsV2
azureuser@azuretestzone.com