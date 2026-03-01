# terraform/modules/key_vault/outputs.tf

output "id" {
  description = "Key Vault resource ID"
  value       = azurerm_key_vault.main.id
}

output "name" {
  description = "Key Vault name"
  value       = azurerm_key_vault.main.name
}

output "vault_uri" {
  description = "Key Vault URI"
  value       = azurerm_key_vault.main.vault_uri
}

output "secret_uris" {
  description = "Map of secret name to URI"
  value       = { for k, s in azurerm_key_vault_secret.secrets : k => s.id }
}
