#########################################################################################
# Configure a new session host
#########################################################################################

data "azurerm_virtual_machine" "this" {
  name                = var.vm_name
  resource_group_name = var.rg_name
}

#read in the session script and populate the variables
data "template_file" "session_config" {
  template = file("${path.module}/rds_session_config.ps1")

  vars = {
  }
}

#configure the session server with all of the dsc modules
resource "azurerm_virtual_machine_extension" "configure_session" {
  name                 = "configure_session"
  virtual_machine_id   = data.azurerm_virtual_machine.this.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  protected_settings = <<PROTECTED_SETTINGS
    {
        "commandToExecute": "powershell -command \"[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(data.template_file.session_config.rendered)}')) | Out-File -filepath rds_session_config.ps1\" && powershell -ExecutionPolicy Unrestricted -File rds_session_config.ps1 exit 0"
    }
PROTECTED_SETTINGS
}
