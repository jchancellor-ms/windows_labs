#get the details for the issue from the vault
#requires the automation account to have secret read permissions
#assumes the vaults were created as separate resources
data "azurerm_key_vault_secret" "digicert_org" {
  name         = var.org_secret_name
  key_vault_id = var.digicert_vault_id
}

data "azurerm_key_vault_secret" "digicert_account" {
  name         = var.account_secret_name
  key_vault_id = var.digicert_vault_id
}

data "azurerm_key_vault_secret" "digicert_apikey" {
  name         = var.apikey_secret_name
  key_vault_id = var.digicert_vault_id
}

resource "azurerm_key_vault_certificate_issuer" "digicert_issuer" {
  name          = "digicert-issuer"
  org_id        = data.azurerm_key_vault_secret.digicert_org.value
  key_vault_id  = var.issuer_vault_id
  provider_name = "DigiCert"
  account_id    = data.azurerm_key_vault_secret.digicert_account.value
  password      = data.azurerm_key_vault_secret.digicert_apikey.value
}
