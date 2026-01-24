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

  # Standard name pattern: {prefix}-{project}-{name}-{env}
  standard_name = "${lookup(local.prefixes, var.resource_type, var.resource_type)}-${var.project}-${var.name}-${var.environment}"

  # Storage accounts: no hyphens, max 24 chars, lowercase only
  storage_name = lower(substr(replace("${var.project}${var.name}${var.environment}", "-", ""), 0, 24))

  # Key Vault: max 24 chars, alphanumeric and hyphens only
  # Include pattern_name when provided to avoid conflicts across patterns
  keyvault_base = var.pattern_name != "" ? "kv-${var.project}-${var.pattern_name}" : "kv-${var.project}-${var.name}"
  keyvault_name = substr("${local.keyvault_base}-${var.environment}", 0, 24)

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
