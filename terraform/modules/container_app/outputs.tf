# terraform/modules/container_app/outputs.tf

output "id" {
  description = "Container App ID"
  value       = azurerm_container_app.main.id
}

output "name" {
  description = "Container App name"
  value       = azurerm_container_app.main.name
}

output "fqdn" {
  description = "Container App FQDN (if ingress enabled)"
  value       = try(azurerm_container_app.main.ingress[0].fqdn, null)
}

output "url" {
  description = "Container App URL (if ingress enabled)"
  value       = try("https://${azurerm_container_app.main.ingress[0].fqdn}", null)
}

output "environment_id" {
  description = "Container App Environment ID"
  value       = local.environment_id
}

output "latest_revision_name" {
  description = "Latest revision name"
  value       = azurerm_container_app.main.latest_revision_name
}

output "principal_id" {
  description = "System-assigned managed identity principal ID (null if not enabled)"
  value       = try(azurerm_container_app.main.identity[0].principal_id, null)
}
