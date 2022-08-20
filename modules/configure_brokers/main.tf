#########################################################################################
# Configure the broker if this is a broker host
#########################################################################################

data "azurerm_virtual_machine" "this" {
  name                = var.vm_name
  resource_group_name = var.rg_name
}

#read in the broker script and populate the variables
data "template_file" "broker_config" {
  template = file("${path.module}/rds_broker_config_simple.ps1")

  vars = {
    vm_name     = var.vm_name
    sql_vm_name = var.sql_vm_name
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
        "commandToExecute": "powershell -command \"[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(data.template_file.broker_config.rendered)}')) | Out-File -filepath rds_broker_config.ps1\" && powershell -ExecutionPolicy Unrestricted -File rds_broker_config.ps1 exit 0"
    }
PROTECTED_SETTINGS
}

#Add to the LB backend pool after the configuration script completes
resource "azurerm_lb_backend_address_pool_address" "this_broker" {
  name                    = "${var.vm_name}-broker-ip"
  backend_address_pool_id = var.backend_address_pool_id
  virtual_network_id      = var.virtual_network_id
  ip_address              = data.azurerm_virtual_machine.this.private_ip_address

  depends_on = [
    azurerm_virtual_machine_extension.configure_broker
  ]
}

output "testoutput" {
  value = data.template_file.broker_config.rendered
}
