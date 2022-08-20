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

#create the SQL virtual machine
resource "azurerm_windows_virtual_machine" "lab_sql" {
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
    publisher = "MicrosoftSQLServer"
    offer     = "sql2019-ws2019"
    sku       = "standard-gen2"
    version   = "15.0.220614"
  }
}

resource "azurerm_managed_disk" "sql_data" {
  name                 = "${var.vm_name}-DATA"
  location             = var.rg_location
  resource_group_name  = var.rg_name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 128
}

resource "azurerm_managed_disk" "sql_logs" {
  name                 = "${var.vm_name}-LOGS"
  location             = var.rg_location
  resource_group_name  = var.rg_name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 128
}

resource "azurerm_virtual_machine_data_disk_attachment" "sql_data" {
  managed_disk_id    = azurerm_managed_disk.sql_data.id
  virtual_machine_id = azurerm_windows_virtual_machine.lab_sql.id
  lun                = "0"
  caching            = "ReadOnly"
}

resource "azurerm_virtual_machine_data_disk_attachment" "sql_logs" {
  managed_disk_id    = azurerm_managed_disk.sql_logs.id
  virtual_machine_id = azurerm_windows_virtual_machine.lab_sql.id
  lun                = "1"
  caching            = "ReadOnly"
}

#get dc password
data "azurerm_key_vault_secret" "dc_join_password" {
  name         = "${var.dc_vm_name}-password"
  key_vault_id = var.key_vault_id
}

resource "azurerm_virtual_machine_extension" "join_domain_sql" {
  name                       = "join-domain"
  virtual_machine_id         = azurerm_windows_virtual_machine.lab_sql.id
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

#create initial login password
resource "random_password" "sqlpass" {
  length           = 20
  special          = true
  override_special = "_-!."
}

#store the initial password in a key vault secret
resource "azurerm_key_vault_secret" "sqlvmpassword" {
  name         = "${var.vm_name}-sqladmin-password"
  value        = random_password.sqlpass.result
  key_vault_id = var.key_vault_id
  depends_on   = [var.key_vault_id]
}

#Create a share and copy the sql client msi into it
data "template_file" "sql_config" {
  template = file("${path.module}/sql_script.ps1")
  vars = {

  }
}

resource "azurerm_virtual_machine_extension" "configure_sql" {
  name                 = "configure_data_disks"
  virtual_machine_id   = azurerm_windows_virtual_machine.lab_sql.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  protected_settings = <<PROTECTED_SETTINGS
    {
        "commandToExecute": "powershell -command \"[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(data.template_file.sql_config.rendered)}')) | Out-File -filepath sql_script.ps1\" && powershell -ExecutionPolicy Unrestricted -File sql_script.ps1"
    }
PROTECTED_SETTINGS

  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.sql_data,
    azurerm_virtual_machine_data_disk_attachment.sql_logs,
    azurerm_virtual_machine_extension.join_domain_sql
  ]
}

#Configure the SQL disks and patching
resource "azurerm_mssql_virtual_machine" "azurerm_sqlvmmanagement" {

  virtual_machine_id               = azurerm_windows_virtual_machine.lab_sql.id
  sql_license_type                 = "AHUB"
  sql_connectivity_port            = 1433
  sql_connectivity_type            = "PRIVATE"
  sql_connectivity_update_password = random_password.sqlpass.result
  sql_connectivity_update_username = "sqladmin"

  auto_patching {
    day_of_week                            = "Sunday"
    maintenance_window_duration_in_minutes = 60
    maintenance_window_starting_hour       = 2
  }

  storage_configuration {
    disk_type             = "NEW"     # (Required) The type of disk configuration to apply to the SQL Server. Valid values include NEW, EXTEND, or ADD.
    storage_workload_type = "GENERAL" # (Required) The type of storage workload. Valid values include GENERAL, OLTP, or DW.

    # The storage_settings block supports the following:
    data_settings {
      default_file_path = "f:\\DATA" # (Required) The SQL Server default path
      luns              = [0]        #azurerm_virtual_machine_data_disk_attachment.datadisk_attach[count.index].lun]
    }

    log_settings {
      default_file_path = "g:\\LOGS" # (Required) The SQL Server default path
      luns              = [1]        #azurerm_virtual_machine_data_disk_attachment.logdisk_attach[count.index].lun] # (Required) A list of Logical Unit Numbers for the disks.
    }

  }
  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.sql_data,
    azurerm_virtual_machine_data_disk_attachment.sql_logs,
    azurerm_virtual_machine_extension.configure_sql
  ]
}






