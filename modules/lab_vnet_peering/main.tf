
resource "azurerm_virtual_network_peering" "hub_owned_peer" {
  name                      = "${var.spoke_vnet_name}-link"
  resource_group_name       = var.rg_name
  virtual_network_name      = var.hub_vnet_name
  remote_virtual_network_id = var.spoke_vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "spoke_owned_peer" {
  name                      = "${var.hub_vnet_name}-link"
  resource_group_name       = var.rg_name
  virtual_network_name      = var.spoke_vnet_name
  remote_virtual_network_id = var.hub_vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}