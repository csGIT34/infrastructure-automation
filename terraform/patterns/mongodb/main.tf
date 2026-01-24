# terraform/patterns/mongodb/main.tf
# MongoDB Pattern - Cosmos DB with MongoDB API

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
  backend "azurerm" {
    use_oidc = true
  }
}

provider "azurerm" {
  features {}
  use_oidc = true
}

provider "azuread" {
  use_oidc = true
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------
variable "project" { type = string }
variable "environment" { type = string }
variable "name" { type = string }
variable "owners" { type = list(string) }
variable "business_unit" { type = string }
variable "location" {
  type    = string
  default = "eastus"
}

variable "pattern_name" {
  description = "Pattern name for resource group naming"
  type        = string
  default     = "mongodb"
}

# Sizing-resolved
variable "throughput" {
  type    = number
  default = 400
}
variable "max_throughput" {
  type    = number
  default = 4000
}
variable "enable_automatic_failover" {
  type    = bool
  default = false
}
variable "consistency_level" {
  type    = string
  default = "Session"
}

# Pattern-specific
variable "enable_diagnostics" {
  type    = bool
  default = false
}
variable "enable_access_review" {
  type    = bool
  default = false
}
variable "purge_protection" {
  type    = bool
  default = false
}
variable "geo_redundant_backup" {
  type    = bool
  default = false
}
variable "access_reviewers" {
  type    = list(string)
  default = []
}
variable "log_analytics_workspace_id" {
  type    = string
  default = ""
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------
module "naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "resource_group"
  name          = var.name
  business_unit = var.business_unit
  pattern_name  = var.pattern_name
}

resource "azurerm_resource_group" "main" {
  name     = module.naming.resource_group_name
  location = var.location
  tags     = module.naming.tags
}

# -----------------------------------------------------------------------------
# MongoDB (base module)
# -----------------------------------------------------------------------------
module "mongodb_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "mongodb"
  name          = var.name
  business_unit = var.business_unit
}

module "mongodb" {
  source = "../../modules/mongodb"

  name                = module.mongodb_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    throughput                = var.throughput
    max_throughput            = var.max_throughput
    enable_automatic_failover = var.enable_automatic_failover
    consistency_level         = var.consistency_level
  }
  tags = module.naming.tags
}

# -----------------------------------------------------------------------------
# Key Vault
# -----------------------------------------------------------------------------
module "keyvault_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "keyvault"
  name          = var.name
  business_unit = var.business_unit
  pattern_name  = var.pattern_name
}

module "keyvault" {
  source = "../../modules/keyvault"

  name                = module.keyvault_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = { sku = "standard", rbac_enabled = true }
  secrets = {
    "mongodb-connection-string" = module.mongodb.connection_string
    "mongodb-endpoint"          = module.mongodb.endpoint
  }
  tags = module.naming.tags
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
module "security_groups" {
  source       = "../../modules/security-groups"
  project      = var.project
  environment  = var.environment
  groups = [
    { suffix = "mongo-readers", description = "Read access to ${var.name} MongoDB" },
    { suffix = "mongo-admins", description = "Admin access to ${var.name} MongoDB" }
  ]
  owner_emails = var.owners
}

# -----------------------------------------------------------------------------
# RBAC
# -----------------------------------------------------------------------------
module "rbac" {
  source = "../../modules/rbac-assignments"
  assignments = [
    {
      principal_id         = module.security_groups.group_ids["mongo-readers"]
      role_definition_name = "Key Vault Secrets User"
      scope                = module.keyvault.vault_id
    },
    {
      principal_id         = module.security_groups.group_ids["mongo-admins"]
      role_definition_name = "Key Vault Secrets Officer"
      scope                = module.keyvault.vault_id
    },
    {
      principal_id         = module.security_groups.group_ids["mongo-admins"]
      role_definition_name = "Cosmos DB Operator"
      scope                = module.mongodb.account_id
    }
  ]
}

# -----------------------------------------------------------------------------
# Access Review (prod only)
# -----------------------------------------------------------------------------
module "access_review" {
  source = "../../modules/access-review"
  count  = var.enable_access_review && length(var.access_reviewers) > 0 ? 1 : 0

  group_id        = module.security_groups.group_ids["mongo-admins"]
  group_name      = module.security_groups.group_names["mongo-admins"]
  reviewer_emails = var.access_reviewers
  frequency       = "quarterly"
}

# -----------------------------------------------------------------------------
# Diagnostics (staging/prod)
# -----------------------------------------------------------------------------
module "diagnostics" {
  source = "../../modules/diagnostic-settings"
  count  = var.enable_diagnostics && var.log_analytics_workspace_id != "" ? 1 : 0

  name                       = module.mongodb_naming.name
  target_resource_id         = module.mongodb.account_id
  log_analytics_workspace_id = var.log_analytics_workspace_id
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "mongodb" {
  value = {
    endpoint   = module.mongodb.endpoint
    account_id = module.mongodb.account_id
  }
}

output "keyvault" {
  value = { name = module.keyvault.vault_name, uri = module.keyvault.vault_uri }
}

output "resource_group" { value = azurerm_resource_group.main.name }
output "security_groups" { value = module.security_groups.group_names }
