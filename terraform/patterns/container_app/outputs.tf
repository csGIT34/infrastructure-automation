# terraform/patterns/container_app/outputs.tf

output "container_app_id" {
  description = "Container App ID"
  value       = module.container_app.id
}

output "container_app_name" {
  description = "Container App name"
  value       = module.container_app.name
}

output "container_app_fqdn" {
  description = "Container App FQDN"
  value       = module.container_app.fqdn
}

output "container_app_url" {
  description = "Container App URL"
  value       = module.container_app.url
}

output "environment_id" {
  description = "Container App Environment ID"
  value       = module.container_app.environment_id
}

output "resource_group_name" {
  description = "Resource group name"
  value       = module.resource_group.name
}

output "security_groups" {
  description = "Security group details"
  value       = module.security_groups.groups
}
