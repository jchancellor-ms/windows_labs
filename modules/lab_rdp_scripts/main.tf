#########################################################################################
# Use the gateway host to create an initial 3-node farm using the first vm of each type
#########################################################################################
data "template_file" "rdp_config" {
  template = file("${path.module}/rds_farm_creation.ps1")

  vars = {
    active_directory_domain = var.active_directory_domain
    gateway_vm_name         = var.gateway_vm_name
    session_vm_name         = var.session_vm_name
    broker_vm_name          = var.broker_vm_name
    #gmsaaccount      = "${(split(".", var.active_directory_domain))[0]}\\${var.gmsa_account_name}$"
    #gateway_vm_login = "${(split(".", var.active_directory_domain))[0]}\\${var.gateway_vm_name}$"
    gmsaaccount                   = "${var.gmsa_account_name}$"
    gateway_vm_login              = "${var.gateway_vm_name}$"
    active_directory_domain       = var.active_directory_domain
    active_directory_netbios_name = (split(".", var.active_directory_domain))[0]
    azureuser_password            = random_password.userpass.result
    vm_name                       = var.vm_name
    session_host_group            = var.session_host_group

    password                      = random_password.userpass.result
    active_directory_domain       = var.active_directory_domain
    active_directory_netbios_name = (split(".", var.active_directory_domain))[0]
    broker_ip                     = var.broker_lb_ip_address
    gmsa_account_name             = var.gmsa_account_name
    broker_group_name             = var.broker_group_name
    session_group_name            = var.session_group_name
    broker_record_name            = var.broker_record_name
  }
}

#if last broker, configure the rdp farm
resource "azurerm_virtual_machine_extension" "configure_rdp" {
  count = var.is_farm_config ? 1 : 0

  name                 = "configure_rdp"
  virtual_machine_id   = azurerm_windows_virtual_machine.this.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  protected_settings = <<PROTECTED_SETTINGS
    {
        "commandToExecute": "powershell -command \"[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(data.template_file.rdp_config[0].rendered)}')) | Out-File -filepath rds_farm_creation.ps1\" && powershell -ExecutionPolicy Unrestricted -File rds_farm_creation.ps1"
    }
PROTECTED_SETTINGS
}




#########################################################################################
# Create a share for the user disks if this is the session host
#########################################################################################
resource "azurerm_managed_disk" "share_data" {
  count                = var.is_smb_host ? 1 : 0
  name                 = "${var.vm_name}-SHARES"
  location             = var.rg_location
  resource_group_name  = var.rg_name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 128
}

resource "azurerm_virtual_machine_data_disk_attachment" "share_data" {
  count              = var.is_smb_host ? 1 : 0
  managed_disk_id    = azurerm_managed_disk.share_data[0].id
  virtual_machine_id = azurerm_windows_virtual_machine.this.id
  lun                = "0"
  caching            = "ReadOnly"
}

data "template_file" "share_config" {
  count    = var.is_smb_host ? 1 : 0
  template = file("${path.module}/smb_script_template.ps1")

  vars = {
    sessionhost = "${var.vm_name}$"
    dc_vm_name  = var.dc_vm_name
  }
}

#add the UPD drive and shares with permissions
resource "azurerm_virtual_machine_extension" "configure_share" {
  count = var.is_smb_host ? 1 : 0

  name                 = "configure_upd_share"
  virtual_machine_id   = azurerm_windows_virtual_machine.this.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  protected_settings = <<PROTECTED_SETTINGS
    {
        "commandToExecute": "powershell -command \"[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(data.template_file.share_config[0].rendered)}')) | Out-File -filepath upd_share.ps1\" && powershell -ExecutionPolicy Unrestricted -File upd_share.ps1"
    }
PROTECTED_SETTINGS

  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.share_data
  ]

}

#########################################################################################
# Create the farm if this is the gateway host
#########################################################################################
data "template_file" "rdp_config" {
  count    = var.is_farm_config ? 1 : 0
  template = file("${path.module}/rds_farm_creation.ps1")

  vars = {
    active_directory_domain = var.active_directory_domain
    gateway_vm_name         = "${var.vm_name}.${var.active_directory_domain}"
    session_vm_name         = "${var.session_vm_name}.${var.active_directory_domain}"
    broker_vm_name          = "${var.broker_vm_name}.${var.active_directory_domain}"
  }
}

#if last broker, configure the rdp farm
resource "azurerm_virtual_machine_extension" "configure_rdp" {
  count = var.is_farm_config ? 1 : 0

  name                 = "configure_rdp"
  virtual_machine_id   = azurerm_windows_virtual_machine.this.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  protected_settings = <<PROTECTED_SETTINGS
    {
        "commandToExecute": "powershell -command \"[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(data.template_file.rdp_config[0].rendered)}')) | Out-File -filepath rds_farm_creation.ps1\" && powershell -ExecutionPolicy Unrestricted -File rds_farm_creation.ps1"
    }
PROTECTED_SETTINGS
}