#export the keyvault id
output "keyvault_id" {
  value = azurerm_key_vault.infra_vault.id
}

output "digicert_issuer_id" {
  value = azurerm_key_vault_certificate_issuer.digicert_issuer.id
}

output "digicert_issuer_name" {
  value = "digicert-issuer"
}