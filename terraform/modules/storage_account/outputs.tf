# terraform/modules/storage_account/outputs.tf

output "id" {
  description = "Storage account ID"
  value       = azurerm_storage_account.main.id
}

output "name" {
  description = "Storage account name"
  value       = azurerm_storage_account.main.name
}

output "primary_blob_endpoint" {
  description = "Primary blob endpoint URL"
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "containers" {
  description = "List of created container names"
  value       = [for c in azurerm_storage_container.containers : c.name]
}
