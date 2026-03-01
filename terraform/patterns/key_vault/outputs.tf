# terraform/patterns/key_vault/outputs.tf

output "key_vault_id" {
  description = "Key Vault resource ID"
  value       = module.key_vault.id
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
