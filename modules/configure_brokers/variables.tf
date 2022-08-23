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