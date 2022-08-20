data "azurerm_key_vault_certificate" "wildcard" {
  name         = var.wildcard_certificate_name
  key_vault_id = var.wildcard_keyvault_id
}


#create initial login password
resource "random_password" "userpass" {
  length           = 20
  special          = true
  override_special = "_-!."
}

#store the initial password in a key vault secret
resource "azurerm_key_vault_secret" "vmpassword" {
  name         = "${var.vm_name}-password"
  value        = random_password.userpass.result
  key_vault_id = var.key_vault_id
  depends_on   = [var.key_vault_id]
}

#create the nic
resource "azurerm_network_interface" "testnic" {
  name                = "${var.vm_name}-nic-1"
  location            = var.rg_location
  resource_group_name = var.rg_name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

#create the virtual machine
resource "azurerm_windows_virtual_machine" "this" {
  name                     = var.vm_name
  resource_group_name      = var.rg_name
  location                 = var.rg_location
  size                     = var.vm_sku
  admin_username           = "azureuser"
  admin_password           = random_password.userpass.result
  license_type             = "Windows_Server"
  enable_automatic_updates = true
  patch_mode               = "AutomaticByOS"
  availability_set_id      = var.availability_set_id

  network_interface_ids = [
    azurerm_network_interface.testnic.id,
  ]

  os_disk {
    name                 = "${var.vm_name}-OS"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  #Add the wildcard certificate locally on the virtual machine
  secret {
    key_vault_id = var.wildcard_keyvault_id
    certificate {
      store = "My"
      url   = data.azurerm_key_vault_certificate.wildcard.secret_id
    }
  }
}


#get dc password
data "azurerm_key_vault_secret" "dc_join_password" {
  name         = "${var.dc_vm_name}-password"
  key_vault_id = var.key_vault_id
}

resource "azurerm_virtual_machine_extension" "join_domain_this" {
  name                       = "join-domain"
  virtual_machine_id         = azurerm_windows_virtual_machine.this.id
  publisher                  = "Microsoft.Compute"
  type                       = "JsonADDomainExtension"
  type_handler_version       = "1.3"
  auto_upgrade_minor_version = true


  settings = <<SETTINGS
    {
        "Name": "${var.active_directory_domain}",
        "OUPath": "${var.ou_path != null ? var.ou_path : ""}",
        "User": "azureuser@${var.active_directory_domain}", 
        "Restart": "true",
        "Options": "3"
    }
SETTINGS

  protected_settings = <<SETTINGS
    {
        "Password": "${data.azurerm_key_vault_secret.dc_join_password.value}"
    }
SETTINGS

}


