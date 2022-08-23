#create a vnet with single subnet
resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = var.rg_location
  resource_group_name = var.rg_name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "subnets" {
  for_each             = { for subnet in var.subnets : subnet.name => subnet }
  name                 = each.value.name
  resource_group_name  = var.rg_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = each.value.address_prefix

}

resource "azurerm_virtual_network_dns_servers" "spoke_dns" {
  count              = var.is_spoke ? 1 : 0
  virtual_network_id = azurerm_virtual_network.vnet.id
  dns_servers        = var.dns_servers
}

resource "azurerm_network_security_group" "subnets" {
  for_each             = { for subnet in var.subnets : subnet.name => subnet  if (subnet.name != "AzureBastionSubnet" && subnet.name != "AzureFirewallSubnet" && subnet.name != "GatewaySubnet")  }
  name                = each.value.name
  location            = var.rg_location
  resource_group_name = var.rg_name

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "subnets" {
  for_each             = { for subnet in var.subnets : subnet.name => subnet if (subnet.name != "AzureBastionSubnet" && subnet.name != "AzureFirewallSubnet" && subnet.name != "GatewaySubnet")  }
  subnet_id                 = azurerm_subnet.subnets[each.value.name].id
  network_security_group_id = azurerm_network_security_group.subnets[each.value.name].id
}