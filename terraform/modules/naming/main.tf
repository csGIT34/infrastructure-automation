# terraform/modules/naming/main.tf
# Generates consistent resource names across all patterns

terraform {
  required_version = ">= 1.5.0"
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "resource_type" {
  description = "Type of resource to generate name for"
  type        = string
}

variable "name" {
  description = "Resource name suffix"
  type        = string
}

variable "business_unit" {
  description = "Business unit for tagging"
  type        = string
  default     = ""
}

variable "pattern_name" {
  description = "Pattern name for unique resource group naming"
  type        = string
  default     = ""
}

locals {
  # Azure resource naming prefixes
  prefixes = {
    keyvault         = "kv"
    postgresql       = "psql"
    mongodb          = "cosmos"
    storage_account  = "st"
    function_app     = "func"
    resource_group   = "rg"
    security_group   = "sg"
    azure_sql        = "sql"
    eventhub         = "evh"
    static_web_app   = "swa"
    aks_namespace    = "ns"
    linux_vm         = "vm"
    private_endpoint = "pe"
    log_analytics    = "log"
    app_insights     = "appi"
    service_plan     = "asp"
  }

  # Environment abbreviations for constrained resources
  env_abbrev = {
    dev     = "d"
    staging = "s"
    prod    = "p"
  }

  # Standard name pattern: {prefix}-{project}-{name}-{env}
  standard_name = "${lookup(local.prefixes, var.resource_type, var.resource_type)}-${var.project}-${var.name}-${var.environment}"

  # Storage accounts: no hyphens, max 24 chars, lowercase only
  # Format: st{project}{name}{env_abbrev} - use abbreviation to save chars
  # Clean project and name by removing hyphens
  storage_project = lower(replace(var.project, "-", ""))
  storage_suffix  = lower(replace(var.name, "-", ""))
  storage_env     = lookup(local.env_abbrev, var.environment, substr(var.environment, 0, 1))
  # Prefix (2) + env (1) = 3 reserved chars, leaving 21 for project+name
  # Split roughly: 14 for project, 7 for name (adjustable)
  storage_project_max = min(length(local.storage_project), 14)
  storage_suffix_max  = min(length(local.storage_suffix), 21 - local.storage_project_max)
  storage_name = lower(join("", [
    "st",
    substr(local.storage_project, 0, local.storage_project_max),
    substr(local.storage_suffix, 0, local.storage_suffix_max),
    local.storage_env
  ]))

  # Key Vault: max 24 chars, alphanumeric and hyphens only, must end with letter/digit
  # Format: kv-{project}-{name}-{env_abbrev}
  keyvault_env  = lookup(local.env_abbrev, var.environment, substr(var.environment, 0, 1))
  keyvault_base = "kv-${var.project}-${var.name}-${local.keyvault_env}"
  keyvault_name = substr(local.keyvault_base, 0, 24)

  # Select appropriate name based on resource type
  resource_name = var.resource_type == "storage_account" ? local.storage_name : (
    var.resource_type == "keyvault" ? local.keyvault_name : local.standard_name
  )

  # Resource group includes pattern name for uniqueness across patterns
  # If pattern_name is empty, fall back to project-environment only
  resource_group_name = var.pattern_name != "" ? "rg-${var.project}-${var.pattern_name}-${var.environment}" : "rg-${var.project}-${var.environment}"
}

output "name" {
  description = "Generated resource name"
  value       = local.resource_name
}

output "resource_group_name" {
  description = "Generated resource group name"
  value       = local.resource_group_name
}

output "prefix" {
  description = "Prefix used for this resource type"
  value       = lookup(local.prefixes, var.resource_type, var.resource_type)
}

output "tags" {
  description = "Standard tags for the resource"
  value = {
    Project      = var.project
    Environment  = var.environment
    BusinessUnit = var.business_unit
    ManagedBy    = "Terraform-Patterns"
  }
}
