variable "rg_name" {
  type        = string
  description = "The azure resource name for the resource group"
}
variable "rg_location" {
  type        = string
  description = "Resource Group region location"
  default     = "westus2"
}
variable "vm_name" {
  type        = string
  description = "The azure resource name for the virtual machine"
}

variable "dc_vm_name" {
  type        = string
  description = "The azure resource name for the virtual machine"
}

variable "subnet_id" {
  type        = string
  description = "The resource ID for the subnet where the virtual machine will be deployed"
}
variable "vm_sku" {
  type        = string
  description = "The sku value for the virtual machine being deployed"
}
variable "key_vault_id" {
  type        = string
  description = "The resource ID for the key vault where the virtual machine secrets will be deployed"
}
variable "active_directory_domain" {
  type        = string
  description = "The full domain name for the domain being created"
}

variable "ou_path" {
  type        = string
  description = "the OU Path for computer objects being joined to the domain"
  default     = ""
}

variable "gmsa_account_name" {
  type        = string
  description = "The account name for the gmsa broker account"
}

variable "gateway_vm_name" {
  type        = string
  description = "The name for the gateway vm"
}

variable "session_host_group" {
  type        = string
  description = "The name for the AD group holding session hosts"
}

variable "availability_set_id" {
  type        = string
  description = "the resource id of the availability set where this VM will be deployed"
}