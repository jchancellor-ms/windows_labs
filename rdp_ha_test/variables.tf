variable "prefix" {}
variable "region" {}
variable "hub_vnet_address_space" {}
variable "hub_subnets" {}
variable "tags" {}
variable "ad_domain_fullname" {}
variable "spoke_vnet_address_space" {}
variable "spoke_subnets" {}
variable "jumpbox_sku" {}
variable "org_secret_name" {
  type        = string
  description = "secret name for the digicert org"
  sensitive   = true
}

variable "account_secret_name" {
  type        = string
  description = "secret name for the digicert secret"
  sensitive   = true
}

variable "apikey_secret_name" {
  type        = string
  description = "secret name for the digicert apikey"
  sensitive   = true
}

variable "digicert_key_vault" {}
variable "digicert_resource_group_name" {}

#variable "webaccess_fqdn" {}
#variable "session_host_fqdns" {}