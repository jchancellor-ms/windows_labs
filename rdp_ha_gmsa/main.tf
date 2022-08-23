#########################################################################################
# Create the resource names
#########################################################################################
locals {
  name_string_suffix  = var.name_string_suffix
  resource_group_name = "${var.prefix}-rg-${var.region}-${local.name_string_suffix}"
  hub_vnet_name       = "${var.prefix}-vnet-hub-${var.region}-${local.name_string_suffix}"
  spoke_vnet_name     = "${var.prefix}-vnet-spoke-${var.region}-${local.name_string_suffix}"
  keyvault_name       = "${var.prefix}-kv-${var.region}-${local.name_string_suffix}"
  dc_vm_name          = "dc-${var.region}-${local.name_string_suffix}"
  broker_lb_name      = "${var.prefix}-broker-lb-${var.region}-${local.name_string_suffix}"
  web_lb_name         = "${var.prefix}-rdweb-lb-${var.region}-${local.name_string_suffix}"
  web_lb_pip_name     = "${var.prefix}-rdweb-lb-pip-${var.region}-${local.name_string_suffix}"
  gw_lb_name          = "${var.prefix}-gw-lb-${var.region}-${local.name_string_suffix}"
  gw_lb_pip_name      = "${var.prefix}-gw-lb-pip-${var.region}-${local.name_string_suffix}"
  bastion_name        = "${var.prefix}-bastion-${var.region}-${local.name_string_suffix}"

  #jumpbox_name        = "jp-${var.region}-${local.name_string_suffix}"
  sql_vm_name         = "ql-${var.region}-${local.name_string_suffix}"
  sql_server_instance = "MSSQLSERVER"
  sql_client_share    = "sqlclient"

  #rX- prefixes are used to define the host types throughout automation
  rds_farm_vms = [
    "rg-${var.region}-${local.name_string_suffix}-1",
    "rg-${var.region}-${local.name_string_suffix}-2",
    "rs-${var.region}-${local.name_string_suffix}-1",
    "rs-${var.region}-${local.name_string_suffix}-2",
    "rb-${var.region}-${local.name_string_suffix}-1",
    "rb-${var.region}-${local.name_string_suffix}-2",
    "rw-${var.region}-${local.name_string_suffix}-1",
    "rw-${var.region}-${local.name_string_suffix}-2",
    "sc-${var.region}-${local.name_string_suffix}-1"
  ]

  #create string groups for insertion into the DSC template file
  broker_hosts  = join(",", [for vm in local.rds_farm_vms : format("\"%s.${var.domain_fqdn}\"", vm) if substr(vm, 0, 2) == "rb"])
  session_hosts = join(",", [for vm in local.rds_farm_vms : format("\"%s.${var.domain_fqdn}\"", vm) if substr(vm, 0, 2) == "rs"])
  gateway_hosts = join(",", [for vm in local.rds_farm_vms : format("\"%s.${var.domain_fqdn}\"", vm) if substr(vm, 0, 2) == "rg"])
  web_hosts     = join(",", [for vm in local.rds_farm_vms : format("\"%s.${var.domain_fqdn}\"", vm) if substr(vm, 0, 2) == "rw"])
  all_hosts     = join(",", [for vm in local.rds_farm_vms : format("\"%s.${var.domain_fqdn}\"", vm) ])

  group_broker_hosts  = join(",", [for vm in local.rds_farm_vms : format("\"%s$\"", vm) if substr(vm, 0, 2) == "rb"])
  group_session_hosts = join(",", [for vm in local.rds_farm_vms : format("\"%s$\"", vm) if substr(vm, 0, 2) == "rs"])
  group_gateway_hosts = join(",", [for vm in local.rds_farm_vms : format("\"%s$\"", vm) if substr(vm, 0, 2) == "rg"])
  group_web_hosts     = join(",", [for vm in local.rds_farm_vms : format("\"%s$\"", vm) if substr(vm, 0, 2) == "rw"])

  gmsa_account_name  = "brokergmsa"
  broker_group_name  = "broker_hosts"
  session_group_name = "session_hosts"
  gateway_group_name = "gateway_hosts"
  web_group_name     = "web_hosts"

  broker_record_name        = "rdcb"
  gateway_record_name       = "rdgw"
  web_record_name           = "rdweb"
  wildcard_certificate_name = "wildcard"

  collection_name        = "test-collection"
  collection_description = "This is a test-collection"

  ou_name = "sessionhosts"
  ou      = "OU=${local.ou_name},${join(",", [for name in split(".", var.domain_fqdn) : "DC=${name}"])}"
}

output "test-output" {
  value = local.broker_hosts
}


###################################################################
# Create the core infrastructure
###################################################################
#deploy resource group
resource "azurerm_resource_group" "lab_rg" {
  name     = local.resource_group_name
  location = var.region
}

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

#get the key vault details for the vault with the lab wildcard certificate
data "azurerm_key_vault" "digicert_vault" {
  name                = var.digicert_key_vault
  resource_group_name = var.digicert_resource_group_name
}

#create the keyvault to store the password secrets for newly created vms
module "on_prem_keyvault_with_access_policy" {
  source = "../modules/avs_key_vault"

  #values to create the keyvault
  rg_name                   = azurerm_resource_group.lab_rg.name
  rg_location               = azurerm_resource_group.lab_rg.location
  keyvault_name             = local.keyvault_name
  azure_ad_tenant_id        = data.azurerm_client_config.current.tenant_id
  deployment_user_object_id = data.azuread_client_config.current.object_id
  tags                      = var.tags
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

#deploy bastion
module "lab_bastion" {
  source = "../modules/lab_bastion_simple"

  bastion_name      = local.bastion_name
  rg_name           = azurerm_resource_group.lab_rg.name
  rg_location       = azurerm_resource_group.lab_rg.location
  bastion_subnet_id = module.lab_hub_virtual_network.subnet_ids["AzureBastionSubnet"].id
  tags              = var.tags
}

resource "azurerm_log_analytics_workspace" "simple" {
  name                = "rds-lab-la-workspace"
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = var.tags
}
#########################################################################################
# Deploy and configure the DC and SQL resources - In a prod deployment these would be assumed to exist
#########################################################################################
#deploy and configure domain controller
resource "azurerm_availability_set" "domain_controllers" {
  name                = "domain_controllers"
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  tags                = var.tags
}

module "rds_dc" {
  source = "../modules/lab_guest_server_2019_dc_pair"

  rg_name                       = azurerm_resource_group.lab_rg.name
  rg_location                   = azurerm_resource_group.lab_rg.location
  vm_name_1                     = local.dc_vm_name
  subnet_id                     = module.lab_hub_virtual_network.subnet_ids["DCSubnet"].id
  vm_sku                        = "Standard_B4ms"
  key_vault_id                  = module.on_prem_keyvault_with_access_policy.keyvault_id
  active_directory_domain       = var.domain_fqdn
  active_directory_netbios_name = split(".", var.domain_fqdn)[0]
  private_ip_address_1          = cidrhost(module.lab_hub_virtual_network.subnet_ids["DCSubnet"].address_prefixes[0], 4)
  ou_name                       = local.ou_name
  broker_lb_ip_address          = azurerm_lb.broker_lb.private_ip_address
  gmsa_account_name             = local.gmsa_account_name
  broker_group_name             = local.broker_group_name
  session_group_name            = local.session_group_name
  availability_set_id           = azurerm_availability_set.domain_controllers.id
  broker_record_name            = local.broker_record_name

  depends_on = [
    module.on_prem_keyvault_with_access_policy
  ]
}

#give the DC time to finish setting up and reboot if needed (added this to the DC config script.  Can come out if needed)
resource "time_sleep" "wait_600_seconds" {
  depends_on = [module.rds_dc]

  create_duration = "600s"
}

resource "azurerm_availability_set" "sql_servers" {
  name                = "sql_servers"
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  tags                = var.tags
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
  active_directory_domain = var.domain_fqdn
  ou_path                 = "" #update this if we want to explicitly set an OU path
  gmsa_account_name       = local.gmsa_account_name
  gateway_vm_name         = [for vm in local.rds_farm_vms : vm if substr(vm, 0, 2) == "rg"][0] #get the first gateway vm to give it permissions to create the RDS database
  session_host_group      = local.session_group_name
  availability_set_id     = azurerm_availability_set.sql_servers.id

  depends_on = [
    time_sleep.wait_600_seconds,
    module.rds_dc,
    module.on_prem_keyvault_with_access_policy
  ]
}

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

  rg_name                   = azurerm_resource_group.lab_rg.name
  rg_location               = azurerm_resource_group.lab_rg.location
  vm_name                   = each.key
  dc_vm_name                = local.dc_vm_name
  subnet_id                 = module.lab_spoke_virtual_network.subnet_ids["VMSubnet"].id
  vm_sku                    = "Standard_B4ms"
  key_vault_id              = module.on_prem_keyvault_with_access_policy.keyvault_id
  active_directory_domain   = var.domain_fqdn
  ou_path                   = "" #update this if we want to explicitly set an OU path
  availability_set_id       = azurerm_availability_set.rds_farm.id
  wildcard_certificate_name = local.wildcard_certificate_name
  wildcard_keyvault_id      = data.azurerm_key_vault.digicert_vault.id

  depends_on = [
    module.rds_dc,
    module.on_prem_keyvault_with_access_policy,
    time_sleep.wait_600_seconds
  ]
}

#########################################################################################
# Deploy Load Balancers for Broker, Gateway, and Web systems
#########################################################################################
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
resource "azurerm_lb_probe" "broker_probe_3389" {
  loadbalancer_id = azurerm_lb.broker_lb.id
  name            = "broker-rdp-probe"
  port            = 3389
  protocol        = "Tcp"
}

#create a load-balancing rules for the brokers (ports 3389 and 5504)
resource "azurerm_lb_rule" "broker_rule" {
  loadbalancer_id                = azurerm_lb.broker_lb.id
  name                           = "Broker_RDP_Rule_3389"
  protocol                       = "Tcp"
  frontend_port                  = 3389
  backend_port                   = 3389
  frontend_ip_configuration_name = "PrivateFrontEndIP"
  probe_id                       = azurerm_lb_probe.broker_probe_3389.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.brokers.id]
}

resource "azurerm_lb_rule" "broker_rule_2" {
  loadbalancer_id                = azurerm_lb.broker_lb.id
  name                           = "Broker_RDP_Rule_5504"
  protocol                       = "Tcp"
  frontend_port                  = 5504
  backend_port                   = 5504
  frontend_ip_configuration_name = "PrivateFrontEndIP"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.brokers.id]
}

#Store logs in an LA workspace for troubleshooting
resource "azurerm_monitor_diagnostic_setting" "broker_lb_logs" {
  name                           = "${local.broker_lb_name}-diagnostic-setting"
  target_resource_id             = azurerm_lb.broker_lb.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.simple.id
  log_analytics_destination_type = "AzureDiagnostics"

  metric {
    category = "AllMetrics"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }
}

#create a loadbalancer for the web-front
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

#create a backend pool for the web load-balancer
resource "azurerm_lb_backend_address_pool" "web" {
  loadbalancer_id = azurerm_lb.web_lb.id
  name            = "BackEndAddressPool"
}

#create an HTTPS probe
resource "azurerm_lb_probe" "web_probe" {
  loadbalancer_id = azurerm_lb.web_lb.id
  name            = "web-https-probe"
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
  probe_id                       = azurerm_lb_probe.web_probe.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.web.id]
}

#Store logs in an LA workspace for troubleshooting
resource "azurerm_monitor_diagnostic_setting" "web_lb_logs" {
  name                           = "${local.web_lb_name}-diagnostic-setting"
  target_resource_id             = azurerm_lb.web_lb.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.simple.id
  log_analytics_destination_type = "AzureDiagnostics"

  metric {
    category = "AllMetrics"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }
}

#create a loadbalancer for the gateways
resource "azurerm_public_ip" "gw_pip" {
  name                = local.gw_lb_pip_name
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_lb" "gw_lb" {
  name                = local.gw_lb_name
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicFrontEndIP"
    public_ip_address_id = azurerm_public_ip.gw_pip.id
  }
}

resource "azurerm_monitor_diagnostic_setting" "gw_lb_logs" {
  name                           = "${local.gw_lb_name}-diagnostic-setting"
  target_resource_id             = azurerm_lb.gw_lb.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.simple.id
  log_analytics_destination_type = "AzureDiagnostics"

  metric {
    category = "AllMetrics"
    enabled  = true

    retention_policy {
      enabled = false
    }
  }
}

#create a backend pool for the load-balancer
resource "azurerm_lb_backend_address_pool" "gateways" {
  loadbalancer_id = azurerm_lb.gw_lb.id
  name            = "BackEndAddressPool"
}

#create an RDP probe
resource "azurerm_lb_probe" "gw_probe_443" {
  loadbalancer_id = azurerm_lb.gw_lb.id
  name            = "gw-https-probe"
  port            = 443
  protocol        = "Tcp"
}

#create a load-balancing rule for the brokers
resource "azurerm_lb_rule" "gw_rule" {
  loadbalancer_id                = azurerm_lb.gw_lb.id
  name                           = "GW_HTTPS_Rule"
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = "PublicFrontEndIP"
  probe_id                       = azurerm_lb_probe.gw_probe_443.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.gateways.id]
}

resource "azurerm_lb_rule" "gw_rule_2" {
  loadbalancer_id                = azurerm_lb.gw_lb.id
  name                           = "GW_RDW_UDP_Rule"
  protocol                       = "Udp"
  frontend_port                  = 3391
  backend_port                   = 3391
  frontend_ip_configuration_name = "PublicFrontEndIP"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.gateways.id]
}

#########################################################################################
# Add systems to load-balancers and deploy custom script extension to install dsc powershell modules
#########################################################################################
module "configure_brokers" {
  source   = "../modules/configure_brokers"
  for_each = toset([for vm in local.rds_farm_vms : vm if substr(vm, 0, 2) == "rb"])

  rg_name                 = azurerm_resource_group.lab_rg.name
  vm_name                 = each.key
  backend_address_pool_id = azurerm_lb_backend_address_pool.brokers.id
  virtual_network_id      = module.lab_spoke_virtual_network.vnet_id
  sql_vm_name             = local.sql_vm_name

  depends_on = [
    module.rds_dc,
    module.on_prem_keyvault_with_access_policy,
    time_sleep.wait_600_seconds,
    module.rds_farm_servers
  ]
}

module "configure_gateways" {
  source   = "../modules/configure_gateways"
  for_each = toset([for vm in local.rds_farm_vms : vm if substr(vm, 0, 2) == "rg"])

  rg_name                 = azurerm_resource_group.lab_rg.name
  vm_name                 = each.key
  backend_address_pool_id = azurerm_lb_backend_address_pool.gateways.id
  virtual_network_id      = module.lab_spoke_virtual_network.vnet_id

  depends_on = [
    module.rds_dc,
    module.on_prem_keyvault_with_access_policy,
    time_sleep.wait_600_seconds,
    module.rds_farm_servers #,  module.configure_rds_farm
  ]
}

module "configure_web" {
  source   = "../modules/configure_web"
  for_each = toset([for vm in local.rds_farm_vms : vm if substr(vm, 0, 2) == "rw"])

  rg_name                 = azurerm_resource_group.lab_rg.name
  vm_name                 = each.key
  backend_address_pool_id = azurerm_lb_backend_address_pool.web.id
  virtual_network_id      = module.lab_spoke_virtual_network.vnet_id

  depends_on = [
    module.rds_dc,
    module.on_prem_keyvault_with_access_policy,
    time_sleep.wait_600_seconds,
    module.rds_farm_servers #,  module.configure_rds_farm
  ]
}

module "configure_session_hosts" {
  source   = "../modules/configure_session_hosts"
  for_each = toset([for vm in local.rds_farm_vms : vm if substr(vm, 0, 2) == "rs"])

  rg_name = azurerm_resource_group.lab_rg.name
  vm_name = each.key

  depends_on = [
    module.rds_dc,
    module.on_prem_keyvault_with_access_policy,
    time_sleep.wait_600_seconds,
    module.rds_farm_servers #,  module.configure_rds_farm
  ]
}

#########################################################################################
# Create the dsc config data template file 
#########################################################################################
data "azurerm_key_vault_certificate" "wildcard" {
  name         = local.wildcard_certificate_name
  key_vault_id = data.azurerm_key_vault.digicert_vault.id
}

data "template_file" "farm_config" {
  template = file("${path.module}/../modules/lab_rdp_scripts/dsc_deploy_template.ps1")

  vars = {

    broker_group_name        = local.broker_group_name
    session_group_name       = local.session_group_name
    gateway_group_name       = local.gateway_group_name
    web_group_name           = local.web_group_name
    broker_hosts             = local.broker_hosts
    session_hosts            = local.session_hosts
    gateway_hosts            = local.gateway_hosts
    web_hosts                = local.web_hosts
    broker_record_name       = local.broker_record_name
    gateway_record_name      = local.gateway_record_name
    web_record_name          = local.web_record_name
    broker_lb_ip_address     = azurerm_lb.broker_lb.private_ip_address
    gateway_lb_ip_address    = azurerm_public_ip.gw_pip.ip_address
    web_lb_ip_address        = azurerm_public_ip.web_pip.ip_address
    domain_name              = split(".", var.domain_fqdn)[0]
    domain_fqdn              = var.domain_fqdn
    sql_server               = local.sql_vm_name
    sql_server_instance      = local.sql_server_instance
    sql_client_share         = local.sql_client_share
    sql_admin                = "sqladmin"
    sql_password             = module.sql_server_1.sqladmin_password
    enable_gmsa              = var.enable_gmsa
    broker_gmsa_account_name = local.gmsa_account_name
    admin_user               = "azureuser"
    admin_password           = module.rds_dc.dc_join_password
    thumbprint               = data.azurerm_key_vault_certificate.wildcard.thumbprint
    validation_key           = var.validation_key
    decryption_key           = var.decryption_key
    collection_name          = local.collection_name
    collection_description   = local.collection_description
    all_hosts                = local.all_hosts
    group_broker_hosts       = local.group_broker_hosts
    group_gateway_hosts      = local.group_gateway_hosts
    group_session_hosts      = local.group_session_hosts
    group_web_hosts          = local.group_web_hosts
  }
}

output "psd" {
  value = data.template_file.farm_config.rendered
}