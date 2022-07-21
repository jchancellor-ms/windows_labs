variable "digicert_vault_id" {
  type        = string
  description = "resource id of the vault with the digicert connection secrets"
}

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

variable "issuer_vault_id" {
  type        = string
  description = "resource id of the vault where certificates will be issued"
}

