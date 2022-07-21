prefix = "rdplab"
region = "westus2"

hub_vnet_address_space = ["10.15.0.0/16"]
hub_subnets = [
  {
    name           = "GatewaySubnet",
    address_prefix = ["10.15.1.0/24"]
  },
  {
    name           = "RouteServerSubnet",
    address_prefix = ["10.15.2.0/24"]
  },
  {
    name           = "AzureBastionSubnet",
    address_prefix = ["10.15.3.0/24"]
  },
  {
    name           = "JumpBoxSubnet"
    address_prefix = ["10.15.4.0/24"]
  },
  {
    name           = "AzureFirewallSubnet"
    address_prefix = ["10.15.5.0/24"]
  },
  {
    name           = "DCSubnet"
    address_prefix = ["10.15.6.0/24"]
  }
]

spoke_vnet_address_space = ["10.30.0.0/16"]
spoke_subnets = [
  {
    name           = "VMSubnet",
    address_prefix = ["10.30.0.0/24"]
  }
]
ad_domain_fullname = "azuretestzone.com"
jumpbox_sku        = "Standard_D2as_v4"

tags = {
  environment = "RDSLab"
  CreatedBy   = "Terraform"
}

digicert_key_vault           = "certsazuretestzone"
digicert_resource_group_name = "domain_details"
org_secret_name              = "certcentral-organizationnumber"
account_secret_name          = "certcentral-accountnumber"
apikey_secret_name           = "azuretestzonekey-apikey"
