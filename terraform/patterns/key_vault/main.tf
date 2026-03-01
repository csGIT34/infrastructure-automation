# terraform/patterns/key_vault/main.tf
# Key Vault pattern: resource_group + naming + key_vault + security_groups + rbac + diagnostics

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

# 1. Naming
module "naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "keyvault"
  name          = var.name
  business_unit = var.business_unit
  pattern_name  = "keyvault"
}

# 2. Resource Group
module "resource_group" {
  source   = "../../modules/resource_group"
  name     = module.naming.resource_group_name
  location = var.location
  tags     = module.naming.tags
}

# 3. Key Vault
module "key_vault" {
  source                     = "../../modules/key_vault"
  name                       = module.naming.name
  location                   = var.location
  resource_group_name        = module.resource_group.name
  sku_name                   = var.sku_name
  purge_protection_enabled   = var.purge_protection_enabled
  soft_delete_retention_days = var.soft_delete_retention_days
  tags                       = module.naming.tags
}

# 4. Security Groups
module "security_groups" {
  source      = "../../modules/security_groups"
  project     = var.project
  environment = var.environment
  owner_emails = var.owners
  groups = [
    { suffix = "secrets-readers", description = "Key Vault Secrets User access for ${var.project}-${var.name}" },
    { suffix = "secrets-admins", description = "Key Vault Secrets Officer access for ${var.project}-${var.name}" },
  ]
}

# 5. RBAC Assignments
module "rbac" {
  source = "../../modules/rbac_assignments"
  assignments = [
    {
      principal_id         = module.security_groups.group_ids["secrets-readers"]
      role_definition_name = "Key Vault Secrets User"
      scope                = module.key_vault.id
    },
    {
      principal_id         = module.security_groups.group_ids["secrets-admins"]
      role_definition_name = "Key Vault Secrets Officer"
      scope                = module.key_vault.id
    },
  ]
}

# 6. Diagnostic Settings (optional)
module "diagnostics" {
  source = "../../modules/diagnostic_settings"
  count  = var.enable_diagnostics ? 1 : 0

  name                       = module.naming.name
  target_resource_id         = module.key_vault.id
  log_analytics_workspace_id = var.log_analytics_workspace_id
  logs                       = ["AuditEvent"]
  metrics                    = ["AllMetrics"]
}
