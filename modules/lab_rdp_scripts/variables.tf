variable "is_smb_host" {
  type        = bool
  description = "flag for determining if this vm will host a fileshare"
  default     = false
}

variable "is_farm_config" {
  type        = bool
  description = "flag for running the rdp farm install script"
  default     = false
}

variable "session_vm_name" {
  type        = string
  description = "Hostname of the session vm"
  default     = ""
}

variable "broker_vm_name" {
  type        = string
  description = "hostname of the initial broker vm"
  default     = ""
}