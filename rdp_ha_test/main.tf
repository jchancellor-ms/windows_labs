#########################################################################################
# Create the resource names
#########################################################################################
locals {
  name_string_suffix  = "t7"
  resource_group_name = "${var.prefix}-rg-${var.region}-${local.name_string_suffix}"
  hub_vnet_name       = "${var.prefix}-vnet-hub-${var.region}-${local.name_string_suffix}"
  spoke_vnet_name     = "${var.prefix}-vnet-spoke-${var.region}-${local.name_string_suffix}"
  keyvault_name       = "${var.prefix}-kv-${var.region}-${local.name_string_suffix}"
  dc_vm_name          = "dc-${var.region}-${local.name_string_suffix}"
  sql_vm_name         = "ql-${var.region}-${local.name_string_suffix}"
  jumpbox_name        = "jp-${var.region}-${local.name_string_suffix}"

  gmsa_account_name  = "brokergmsa"
  broker_group_name  = "connection_brokers"
  session_group_name = "session_hosts"
  broker_record_name = "rdcb"

  rds_farm_vms = [
    "rg-${var.region}-${local.name_string_suffix}-1",
    "rg-${var.region}-${local.name_string_suffix}-2",
    "rs-${var.region}-${local.name_string_suffix}-1",
    "rs-${var.region}-${local.name_string_suffix}-2",
    "rb-${var.region}-${local.name_string_suffix}-1",
    "rb-${var.region}-${local.name_string_suffix}-2",
    "sc-${var.region}-${local.name_string_suffix}-1"
  ]


  broker_lb_name  = "${var.prefix}-broker-lb-${var.region}-${local.name_string_suffix}"
  web_lb_name     = "${var.prefix}-web-lb-${var.region}-${local.name_string_suffix}"
  web_lb_pip_name = "${var.prefix}-web-lb-pip-${var.region}-${local.name_string_suffix}"
  bastion_name    = "${var.prefix}-bastion-${var.region}-${local.name_string_suffix}"
  ou_name         = "sessionhosts"
  ou              = "OU=${local.ou_name},${join(",", [for name in split(".", var.ad_domain_fullname) : "DC=${name}"])}"
}

#########################################################################################
# Deploy the Resource Group and Networking components
#########################################################################################
#deploy resource group
resource "azurerm_resource_group" "lab_rg" {
  name     = local.resource_group_name
  location = var.region
}

resource "random_string" "namestring" {
  length  = 2
  special = false
  upper   = false
  lower   = true
}

#deploy vnet and subnets
#Create a hub virtual network for the DC and the bastion for management
module "lab_hub_virtual_network" {
  source = "../modules/lab_vnet_variable_subnets"

  rg_name            = azurerm_resource_group.lab_rg.name
  rg_location        = azurerm_resource_group.lab_rg.location
  vnet_name          = local.hub_vnet_name
  vnet_address_space = var.hub_vnet_address_space
  subnets            = var.hub_subnets
  tags               = var.tags
}

#deploy key vault with access policy and certificate issuer
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

data "azurerm_key_vault" "digicert_vault" {
  name                = var.digicert_key_vault
  resource_group_name = var.digicert_resource_group_name
}

module "on_prem_keyvault_with_access_policy" {
  source = "../modules/avs_key_vault"

  #values to create the keyvault
  rg_name            = azurerm_resource_group.lab_rg.name
  rg_location        = azurerm_resource_group.lab_rg.location
  keyvault_name      = local.keyvault_name
  azure_ad_tenant_id = data.azurerm_client_config.current.tenant_id
  #deployment_user_object_id = data.azurerm_client_config.current.object_id
  deployment_user_object_id = data.azuread_client_config.current.object_id #temp fix for az cli breaking change
  tags                      = var.tags
  org_secret_name           = var.org_secret_name
  account_secret_name       = var.account_secret_name
  apikey_secret_name        = var.apikey_secret_name
  digicert_vault_id         = data.azurerm_key_vault.digicert_vault.id
}

#deploy spoke vnet for VM's with custom DNS pointing at DC for domain joins
#create spoke vnet 
module "lab_spoke_virtual_network" {
  source = "../modules/lab_vnet_variable_subnets"

  rg_name            = azurerm_resource_group.lab_rg.name
  rg_location        = azurerm_resource_group.lab_rg.location
  vnet_name          = local.spoke_vnet_name
  vnet_address_space = var.spoke_vnet_address_space
  subnets            = var.spoke_subnets
  tags               = var.tags
  is_spoke           = true
  dns_servers        = [cidrhost(module.lab_hub_virtual_network.subnet_ids["DCSubnet"].address_prefixes[0], 4)]

}

#create peering to hub for spoke
module "azure_vnet_peering_hub_defaults" {
  source = "../modules/lab_vnet_peering"

  spoke_vnet_name = local.spoke_vnet_name
  spoke_vnet_id   = module.lab_spoke_virtual_network.vnet_id
  hub_vnet_name   = local.hub_vnet_name
  hub_vnet_id     = module.lab_hub_virtual_network.vnet_id
  rg_name         = azurerm_resource_group.lab_rg.name

  depends_on = [
    module.lab_hub_virtual_network
  ]
}

#create a loadbalancer for the brokers
resource "azurerm_lb" "broker_lb" {
  name                = local.broker_lb_name
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name               = "PrivateFrontEndIP"
    subnet_id          = module.lab_spoke_virtual_network.subnet_ids["VMSubnet"].id
    private_ip_address = cidrhost(module.lab_spoke_virtual_network.subnet_ids["VMSubnet"].address_prefixes[0], 4)
  }
}

#create a backend pool for the load-balancer
resource "azurerm_lb_backend_address_pool" "brokers" {
  loadbalancer_id = azurerm_lb.broker_lb.id
  name            = "BackEndAddressPool"
}

#create an RDP probe
resource "azurerm_lb_probe" "broker_probe" {
  loadbalancer_id = azurerm_lb.broker_lb.id
  name            = "broker-rdp-probe"
  port            = 3389
  protocol        = "Tcp"
}

#create a load-balancing rule for the brokers
resource "azurerm_lb_rule" "broker_rule" {
  loadbalancer_id                = azurerm_lb.broker_lb.id
  name                           = "Broker_RDP_Rule"
  protocol                       = "Tcp"
  frontend_port                  = 3389
  backend_port                   = 3389
  frontend_ip_configuration_name = "PrivateFrontEndIP"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.brokers.id]
}

#create a loadbalancer for the web-front/gateways
resource "azurerm_public_ip" "web_pip" {
  name                = local.web_lb_pip_name
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}


resource "azurerm_lb" "web_lb" {
  name                = local.web_lb_name
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicFrontEndIP"
    public_ip_address_id = azurerm_public_ip.web_pip.id
  }
}

#create a backend pool for the load-balancer
resource "azurerm_lb_backend_address_pool" "web_gateways" {
  loadbalancer_id = azurerm_lb.web_lb.id
  name            = "BackEndAddressPool"
}

#create an RDP probe
resource "azurerm_lb_probe" "webgw_probe" {
  loadbalancer_id = azurerm_lb.broker_lb.id
  name            = "webgw-https-probe"
  port            = 443
  protocol        = "Tcp"
}

#create a load-balancing rule for the brokers
resource "azurerm_lb_rule" "web_rule" {
  loadbalancer_id                = azurerm_lb.web_lb.id
  name                           = "Web_HTTPS_Rule"
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = "PublicFrontEndIP"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.web_gateways.id]
}


#########################################################################################
# Deploy and configure the DC and SQL resources - In a prod deployment these would be assumed to exist
#########################################################################################


#deploy and configure domain controller
module "rds_dc" {
  source = "../modules/lab_guest_server_2019_dc"

  rg_name                       = azurerm_resource_group.lab_rg.name
  rg_location                   = azurerm_resource_group.lab_rg.location
  vm_name                       = local.dc_vm_name
  subnet_id                     = module.lab_hub_virtual_network.subnet_ids["DCSubnet"].id
  vm_sku                        = "Standard_B2ms"
  key_vault_id                  = module.on_prem_keyvault_with_access_policy.keyvault_id
  active_directory_domain       = var.ad_domain_fullname
  active_directory_netbios_name = split(".", var.ad_domain_fullname)[0]
  private_ip_address            = cidrhost(module.lab_hub_virtual_network.subnet_ids["DCSubnet"].address_prefixes[0], 4)
  ou_name                       = local.ou_name
  broker_lb_ip_address          = azurerm_lb.broker_lb.private_ip_address
  gmsa_account_name             = local.gmsa_account_name
  broker_group_name             = local.broker_group_name
  session_group_name            = local.session_group_name

  broker_record_name = local.broker_record_name

  depends_on = [
    module.on_prem_keyvault_with_access_policy
  ]
}

#give the DC time to finish setting up and reboot if needed (added this to the DC config script.  Can come out if needed)
resource "time_sleep" "wait_600_seconds" {
  depends_on = [module.rds_dc]

  create_duration = "600s"
}

#deploy sql server
module "sql_server_1" {
  source = "../modules/lab_guest_server_2019_sql_standard"

  rg_name                 = azurerm_resource_group.lab_rg.name
  rg_location             = azurerm_resource_group.lab_rg.location
  vm_name                 = local.sql_vm_name
  dc_vm_name              = local.dc_vm_name
  subnet_id               = module.lab_spoke_virtual_network.subnet_ids["VMSubnet"].id
  vm_sku                  = "Standard_B4ms"
  key_vault_id            = module.on_prem_keyvault_with_access_policy.keyvault_id
  active_directory_domain = var.ad_domain_fullname
  ou_path                 = "" #update this if we want to explicitly set an OU path
  gmsa_account_name       = local.gmsa_account_name
  gateway_vm_name         = [for vm in local.rds_farm_vms : vm if substr(vm, 0, 2) == "rg"][0] #get the first gateway vm to give it permissions to create the RDS database
  session_host_group      = local.session_group_name

  depends_on = [
    time_sleep.wait_600_seconds,
    module.rds_dc,
    module.on_prem_keyvault_with_access_policy
  ]
}

#deploy bastion
module "lab_bastion" {
  source = "../modules/lab_bastion_simple"

  bastion_name      = local.bastion_name
  rg_name           = azurerm_resource_group.lab_rg.name
  rg_location       = azurerm_resource_group.lab_rg.location
  bastion_subnet_id = module.lab_hub_virtual_network.subnet_ids["AzureBastionSubnet"].id
  tags              = var.tags
}
#deploy jumpserver
#deploy the jumpbox host 
/*
module "avs_jumpbox" {
  source = "../modules/avs_jumpbox"

  jumpbox_name      = local.jumpbox_name
  jumpbox_sku       = var.jumpbox_sku
  rg_name           = azurerm_resource_group.lab_rg.name
  rg_location       = azurerm_resource_group.lab_rg.location
  jumpbox_subnet_id = module.lab_hub_virtual_network.subnet_ids["JumpBoxSubnet"].id
  admin_username    = "azureuser"
  key_vault_id      = module.on_prem_keyvault_with_access_policy.keyvault_id
  tags              = var.tags


  depends_on = [
    module.on_prem_keyvault_with_access_policy
  ]
}
*/
#########################################################################################
# Deploy farm vms and join to the domain (no customization yet)
#########################################################################################
#Deploy RDP configuration vm's use a single availability set to minimize 
#simultaneous reboots across farm systems for maintenance and patching
resource "azurerm_availability_set" "rds_farm" {
  name                = "rds_farm"
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  tags                = var.tags
}

### Deploy session host
module "rds_farm_servers" {
  source   = "../modules/lab_guest_server_2019_domain_join"
  for_each = toset(local.rds_farm_vms)

  rg_name                 = azurerm_resource_group.lab_rg.name
  rg_location             = azurerm_resource_group.lab_rg.location
  vm_name                 = each.key
  dc_vm_name              = local.dc_vm_name
  subnet_id               = module.lab_spoke_virtual_network.subnet_ids["VMSubnet"].id
  vm_sku                  = "Standard_B2ms"
  key_vault_id            = module.on_prem_keyvault_with_access_policy.keyvault_id
  active_directory_domain = var.ad_domain_fullname
  ou_path                 = "" #update this if we want to explicitly set an OU path
  availability_set_id     = azurerm_availability_set.rds_farm.id

  depends_on = [
    module.rds_dc,
    module.on_prem_keyvault_with_access_policy,
    time_sleep.wait_600_seconds
  ]
}

#########################################################################################
# Deploy the farm configuration scripts
#########################################################################################

module "configure_rds_farm" {
  source = "../modules/configure_initial_rds_farm"

  aduser_password               = module.rds_dc.dc_join_password
  active_directory_netbios_name = split(".", var.ad_domain_fullname)[0]
  broker_group_name             = local.broker_group_name
  session_group_name            = local.session_group_name
  gmsa_account_name             = local.gmsa_account_name
  active_directory_domain       = var.ad_domain_fullname
  broker_record_name            = local.broker_record_name
  broker_ip                     = azurerm_lb.broker_lb.private_ip_address
  sqladmin_password             = module.sql_server_1.sqladmin_password
  vm_name                       = [for vm in local.rds_farm_vms : vm if substr(vm, 0, 2) == "sc"][0]
  rg_name                       = azurerm_resource_group.lab_rg.name
  sql_vm_name                   = local.sql_vm_name
  broker_vm_name                = [for vm in local.rds_farm_vms : vm if substr(vm, 0, 2) == "rb"][0]
  session_vm_name               = [for vm in local.rds_farm_vms : vm if substr(vm, 0, 2) == "rs"][0]
  gateway_vm_name               = [for vm in local.rds_farm_vms : vm if substr(vm, 0, 2) == "rg"][0]

  depends_on = [
    module.rds_dc,
    module.on_prem_keyvault_with_access_policy,
    time_sleep.wait_600_seconds,
    module.rds_farm_servers
  ]
}

output "testoutput" {
  value = module.configure_rds_farm.testoutput
}
/*
#########################################################################################
# Add and Configure the remaining brokers
#########################################################################################
module "configure_brokers" {
  source   = "../modules/configure_brokers"
  for_each = toset([for vm in local.rds_farm_vms : vm if substr(vm, 0, 2) == "rb"])

  rg_name                       = azurerm_resource_group.lab_rg.name
  vm_name                       = each.key
  backend_address_pool_id       = azurerm_lb_backend_address_pool.brokers.id
  virtual_network_id            = module.lab_spoke_virtual_network.vnet_id
  sql_vm_name                   = local.sql_vm_name
  active_directory_domain       = var.ad_domain_fullname
  active_directory_netbios_name = var.ad_domain_fullname
  broker_group_name             = local.broker_group_name
  gmsa_account_name             = local.gmsa_account_name
  broker_record_name            = local.broker_record_name
  first_broker_vm               = [for vm in local.rds_farm_vms : vm if substr(vm, 0, 2) == "rb"][0]

  depends_on = [
    module.rds_dc,
    module.on_prem_keyvault_with_access_policy,
    time_sleep.wait_600_seconds,
    module.rds_farm_servers,
    module.configure_rds_farm
  ]
}




#configure the initial broker vm without running a custom script extension
module "rdp_server_brokers" {
  source = "../modules/lab_guest_server_2019_domain_join"

  for_each                = toset(local.rdp_broker_vm_name)
  rg_name                 = azurerm_resource_group.lab_rg.name
  rg_location             = azurerm_resource_group.lab_rg.location
  vm_name                 = each.key
  dc_vm_name              = local.dc_vm_name
  subnet_id               = module.lab_spoke_virtual_network.subnet_ids["VMSubnet"].id
  vm_sku                  = "Standard_B2ms"
  key_vault_id            = module.on_prem_keyvault_with_access_policy.keyvault_id
  active_directory_domain = var.ad_domain_fullname
  ou_path                 = "" #update this if we want to explicitly set an OU path

  depends_on = [
    module.rds_dc,
    module.on_prem_keyvault_with_access_policy,
    time_sleep.wait_600_seconds
  ]
}

###deploy initial script host that has the remaining server roles.  
###This is a hack to get around limitations related to running multiple 
###Powershell scripts in a specific sequence
module "rdp_server_gateway" {
  source = "../modules/lab_guest_server_2019_domain_join"

  rg_name                 = azurerm_resource_group.lab_rg.name
  rg_location             = azurerm_resource_group.lab_rg.location
  vm_name                 = local.rdp_gateway_vm_name
  dc_vm_name              = local.dc_vm_name
  subnet_id               = module.lab_spoke_virtual_network.subnet_ids["VMSubnet"].id
  vm_sku                  = "Standard_B2ms"
  key_vault_id            = module.on_prem_keyvault_with_access_policy.keyvault_id
  active_directory_domain = var.ad_domain_fullname
  ou_path                 = "" #update this if we want to explicitly set an OU path
  is_farm_config          = true
  session_vm_name         = local.rdp_session_vm_name
  broker_vm_name          = local.rdp_broker_vm_name[0]
  depends_on = [
    module.rds_dc,
    module.on_prem_keyvault_with_access_policy,
    time_sleep.wait_600_seconds,
    module.rdp_server_session,
    module.rdp_server_brokers
  ]
}

module "configure_brokers" {
  source = "../modules/configure_brokers"

  for_each = toset(local.rdp_broker_vm_name)

  rg_name              = azurerm_resource_group.lab_rg.name
  vm_name = each.key
  backend_address_pool_id  = azurerm_lb_backend_address_pool.brokers.id
  virtual_network_id = module.lab_spoke_virtual_network.vnet_id
  sql_vm_name          = local.sql_vm_name
  sql_version_number   = "17"
  active_directory_domain = var.ad_domain_fullname
  broker_record_name   = local.broker_record_name
  gmsa_group_name      = local.gmsa_group_name
  gmsa_account_name    = "${var.ad_domain_fullname}.${local.gmsa_account_name}$"

  depends_on = [
    module.rdp_server_brokers,
    module.rds_dc,
    module.rdp_server_gateway,
    module.sql_server_1,
    module.rdp_server_session
  ]
}

*/