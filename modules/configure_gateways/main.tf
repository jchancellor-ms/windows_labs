#get the current gateway configuration
data "azurerm_virtual_machine" "this" {
  name                = var.vm_name
  resource_group_name = var.rg_name
}

#read in the web script and populate the variables
data "template_file" "gateway_config" {
  template = file("${path.module}/rds_gateway_config.ps1")

  vars = {
  }
}

#configure the gateway server with all of the dsc modules
resource "azurerm_virtual_machine_extension" "configure_gateway" {
  name                 = "configure_gateway"
  virtual_machine_id   = data.azurerm_virtual_machine.this.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  protected_settings = <<PROTECTED_SETTINGS
    {
        "commandToExecute": "powershell -command \"[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(data.template_file.gateway_config.rendered)}')) | Out-File -filepath rds_gateway_config.ps1\" && powershell -ExecutionPolicy Unrestricted -File rds_gateway_config.ps1 exit 0"
    }
PROTECTED_SETTINGS
}

#Add the gateway to the backend address pool for the gateway lb
resource "azurerm_lb_backend_address_pool_address" "gateway" {
  name                    = "${var.vm_name}-gateway-ip"
  backend_address_pool_id = var.backend_address_pool_id
  virtual_network_id      = var.virtual_network_id
  ip_address              = data.azurerm_virtual_machine.this.private_ip_address
}