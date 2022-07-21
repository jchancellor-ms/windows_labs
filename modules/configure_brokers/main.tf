#########################################################################################
# Configure the broker if this is a broker host
#########################################################################################

data "azurerm_virtual_machine" "this" {
  name                = var.vm_name
  resource_group_name = var.rg_name
}

#read in the broker script and populate the variables
data "template_file" "broker_config" {
  template = file("${path.module}/rds_broker_config.ps1")

  vars = {
    vm_name                       = var.vm_name
    sql_vm_name                   = var.sql_vm_name
    broker_record_name            = var.broker_record_name
    broker_group_name             = var.broker_group_name
    gmsa_account_name             = var.gmsa_account_name
    active_directory_domain       = var.active_directory_domain
    active_directory_netbios_name = var.active_directory_netbios_name
    first_broker_vm               = var.first_broker_vm
  }
}

#configure the broker to use sql and the gmsa
resource "azurerm_virtual_machine_extension" "configure_broker" {
  name                 = "configure_broker"
  virtual_machine_id   = data.azurerm_virtual_machine.this.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  protected_settings = <<PROTECTED_SETTINGS
    {
        "commandToExecute": "powershell -command \"[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(data.template_file.broker_config.rendered)}')) | Out-File -filepath rds_broker_config.ps1\" && powershell -ExecutionPolicy Unrestricted -File rds_broker_config.ps1"
    }
PROTECTED_SETTINGS
}

#Add to the LB backend pool
resource "azurerm_lb_backend_address_pool_address" "this_broker" {
  name                    = "${var.vm_name}-broker-ip"
  backend_address_pool_id = var.backend_address_pool_id
  virtual_network_id      = var.virtual_network_id
  ip_address              = data.azurerm_virtual_machine.this.private_ip_address

  depends_on = [
    azurerm_virtual_machine_extension.configure_broker
  ]
}
