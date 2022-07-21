#read in the data for the script host
data "azurerm_virtual_machine" "this" {
  name                = var.vm_name
  resource_group_name = var.rg_name
}

#read in the main RDS script and populate the variables
data "template_file" "broker_config" {
  template = file("${path.module}/rds_farm_creation.ps1")

  vars = {
    aduser_password               = var.aduser_password
    active_directory_netbios_name = var.active_directory_netbios_name
    broker_group_name             = var.broker_group_name
    session_group_name            = var.session_group_name
    gmsa_account_name             = var.gmsa_account_name
    active_directory_domain       = var.active_directory_domain
    broker_record_name            = var.broker_record_name
    broker_ip                     = var.broker_ip
    sqladmin_password             = var.sqladmin_password
    script_vm_name                = var.vm_name
    sql_vm_name                   = var.sql_vm_name
    broker_vm_name                = var.broker_vm_name
    session_vm_name               = var.session_vm_name
    gateway_vm_name               = var.gateway_vm_name
  }
}

#configure the broker to use sql and the gmsa
resource "azurerm_virtual_machine_extension" "configure_farm" {
  name                 = "configure_farm"
  virtual_machine_id   = data.azurerm_virtual_machine.this.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  protected_settings = <<PROTECTED_SETTINGS
    {
        "commandToExecute": "powershell -command \"[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(data.template_file.broker_config.rendered)}')) | Out-File -filepath rds_farm_creation.ps1\" && powershell -ExecutionPolicy Unrestricted -File rds_farm_creation.ps1"
    }
PROTECTED_SETTINGS
}