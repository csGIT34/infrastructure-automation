# terraform/patterns/storage_account/outputs.tf

output "storage_account_id" {
  description = "Storage account ID"
  value       = module.storage_account.id
}

output "storage_account_name" {
  description = "Storage account name"
  value       = module.storage_account.name
}

output "primary_blob_endpoint" {
  description = "Primary blob endpoint URL"
  value       = module.storage_account.primary_blob_endpoint
}

output "containers" {
  description = "List of created container names"
  value       = module.storage_account.containers
}

output "resource_group_name" {
  description = "Resource group name"
  value       = module.resource_group.name
}

output "security_groups" {
  description = "Security group details"
  value       = module.security_groups.groups
}
