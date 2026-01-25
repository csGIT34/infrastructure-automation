# terraform/patterns/api-backend/main.tf
# API Backend Pattern - Function App + Database + Key Vault
# For REST APIs and microservice backends

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = ">= 4.0" }
    azuread = { source = "hashicorp/azuread", version = "~> 2.0" }
    random  = { source = "hashicorp/random", version = "~> 3.0" }
  }
  backend "azurerm" { use_oidc = true }
}

provider "azurerm" {
  features {}
  use_oidc = true
}
provider "azuread" { use_oidc = true }


# Variables
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
  default     = "api-backend"
}

variable "database_type" {
  description = "Database type: azure_sql, postgresql, mongodb, or none"
  type        = string
  default     = "azure_sql"
}

# Sizing
variable "function_sku" {
  type    = string
  default = "FC1"  # Flex Consumption - no VM quota required
}
variable "db_sku" {
  type    = string
  default = "Free"
}

# Pattern-specific
variable "runtime" {
  type    = string
  default = "python"
}
variable "runtime_version" {
  type    = string
  default = ""  # Empty = use module's runtime-appropriate default
}
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

# Resource Group
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

# Function App (API)
module "func_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "function_app"
  name          = var.name
  business_unit = var.business_unit
}

module "function_app" {
  source = "../../modules/function-app"

  name                = module.func_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku             = var.function_sku
    runtime         = var.runtime
    runtime_version = var.runtime_version
    os_type         = "Linux"
  }
  tags = module.naming.tags
}

# Database
module "db_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = var.database_type
  name          = "${var.name}-db"
  business_unit = var.business_unit
}

module "postgresql" {
  source = "../../modules/postgresql"
  count  = var.database_type == "postgresql" ? 1 : 0

  name                = module.db_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config              = { sku = var.db_sku }
  tags                = module.naming.tags
}

module "azure_sql" {
  source = "../../modules/azure-sql"
  count  = var.database_type == "azure_sql" ? 1 : 0

  name                = module.db_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config              = { sku_name = "Basic" }
  tags                = module.naming.tags
}

module "mongodb" {
  source = "../../modules/mongodb"
  count  = var.database_type == "mongodb" ? 1 : 0

  name                = module.db_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config              = {}
  tags                = module.naming.tags
}

# Key Vault
module "keyvault_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "keyvault"
  name          = var.name
  business_unit = var.business_unit
  pattern_name  = var.pattern_name
}

locals {
  db_secrets = var.database_type == "postgresql" ? {
    "db-connection-string" = "Host=${module.postgresql[0].server_fqdn};Database=${module.postgresql[0].database_name};Username=psqladmin"
  } : var.database_type == "azure_sql" ? module.azure_sql[0].secrets_for_keyvault : var.database_type == "mongodb" ? {
    "db-connection-string" = module.mongodb[0].connection_string
  } : {}
}

module "keyvault" {
  source = "../../modules/keyvault"

  name                = module.keyvault_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config              = { sku = "standard", rbac_enabled = true }
  secrets = merge(module.function_app.secrets_for_keyvault, local.db_secrets)
  secrets_user_principal_ids = { "api" = module.function_app.principal_id }
  tags = module.naming.tags
}

# Security Groups
module "security_groups" {
  source       = "../../modules/security-groups"
  project      = var.project
  environment  = var.environment
  groups = [
    { suffix = "api-developers", description = "Developers for ${var.name} API" },
    { suffix = "api-admins", description = "Administrators for ${var.name} API" }
  ]
  owner_emails = var.owners
}

# RBAC
module "rbac" {
  source = "../../modules/rbac-assignments"
  assignments = [
    {
      principal_id         = module.security_groups.group_ids["api-developers"]
      role_definition_name = "Website Contributor"
      scope                = module.function_app.id
    },
    {
      principal_id         = module.security_groups.group_ids["api-admins"]
      role_definition_name = "Key Vault Secrets Officer"
      scope                = module.keyvault.vault_id
    }
  ]
}

# Access Review (prod only)
module "access_review" {
  source = "../../modules/access-review"
  count  = var.enable_access_review ? 1 : 0

  group_id   = module.security_groups.group_ids["api-admins"]
  group_name = module.security_groups.group_names["api-admins"]
  frequency  = "quarterly"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

# Diagnostics (staging/prod)
module "diagnostics" {
  source = "../../modules/diagnostic-settings"
  count  = var.enable_diagnostics && var.log_analytics_workspace_id != "" ? 1 : 0

  name                       = module.func_naming.name
  target_resource_id         = module.function_app.id
  log_analytics_workspace_id = var.log_analytics_workspace_id
}

# Outputs
output "api" {
  value = { name = module.function_app.name, url = module.function_app.url, principal_id = module.function_app.principal_id }
}

output "database" {
  value = var.database_type == "postgresql" ? {
    type = "postgresql", server = module.postgresql[0].server_fqdn, name = module.postgresql[0].database_name
  } : var.database_type == "azure_sql" ? {
    type = "azure_sql", server = module.azure_sql[0].server_fqdn, name = module.azure_sql[0].database_name
  } : var.database_type == "mongodb" ? {
    type = "mongodb", endpoint = module.mongodb[0].endpoint
  } : null
}

output "keyvault" { value = { name = module.keyvault.vault_name, uri = module.keyvault.vault_uri } }
output "resource_group" { value = azurerm_resource_group.main.name }
output "security_groups" { value = module.security_groups.group_names }
