variable "rg_name" {
  type        = string
  description = "The azure resource name for the resource group"
}

variable "vm_name" {
  type        = string
  description = "The azure resource name for the virtual machine"
}

variable "backend_address_pool_id" {
  type        = string
  description = "Azure resource ID for the broker load balancer backend address pool"
  default     = ""
}

variable "virtual_network_id" {
  type        = string
  description = "Azure resource ID for the load balancer virtual network"
  default     = ""
}

variable "sql_vm_name" {
  type        = string
  description = "The azure resource name for the sql virtual machine"
}

variable "active_directory_domain" {
  type        = string
  description = "The full domain name for the domain being created"
}

variable "active_directory_netbios_name" {
  type        = string
  description = "The shortname name for the domain being created"
}

variable "broker_group_name" {
  type        = string
  description = "name for the group where broker servers will be created"
}

variable "gmsa_account_name" {
  type        = string
  description = "name for the gmsa account being created"
}

variable "broker_record_name" {
  type        = string
  description = "name for the a record for broker services"
}

variable "first_broker_vm" {
  type        = string
  description = "name for the first broker vm"
}