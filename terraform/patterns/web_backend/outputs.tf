# terraform/patterns/web_backend/outputs.tf

output "container_app_url" {
  description = "Container App URL"
  value       = module.container_app.url
}

output "container_app_fqdn" {
  description = "Container App FQDN"
  value       = module.container_app.fqdn
}

output "postgresql_fqdn" {
  description = "PostgreSQL server FQDN"
  value       = module.postgresql.fqdn
}

output "database_name" {
  description = "Database name"
  value       = module.postgresql.database_name
}

output "key_vault_name" {
  description = "Key Vault name"
  value       = module.key_vault.name
}

output "key_vault_uri" {
  description = "Key Vault URI"
  value       = module.key_vault.vault_uri
}

output "resource_group_name" {
  description = "Resource group name"
  value       = module.resource_group.name
}

output "security_groups" {
  description = "Security group details"
  value       = module.security_groups.groups
}
