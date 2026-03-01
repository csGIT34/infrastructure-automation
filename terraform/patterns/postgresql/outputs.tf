# terraform/patterns/postgresql/outputs.tf

output "postgresql_id" {
  description = "PostgreSQL server ID"
  value       = module.postgresql.id
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
  description = "Key Vault name (stores connection secrets)"
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
