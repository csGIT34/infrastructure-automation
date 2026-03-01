# terraform/patterns/storage_account/main.tf
# Storage Account pattern: resource_group + naming + storage_account + security_groups + rbac + diagnostics

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
  resource_type = "storage_account"
  name          = var.name
  business_unit = var.business_unit
  pattern_name  = "storage"
}

# 2. Resource Group
module "resource_group" {
  source   = "../../modules/resource_group"
  name     = module.naming.resource_group_name
  location = var.location
  tags     = module.naming.tags
}

# 3. Storage Account
module "storage_account" {
  source              = "../../modules/storage_account"
  name                = module.naming.name
  location            = var.location
  resource_group_name = module.resource_group.name
  account_tier        = var.account_tier
  replication_type    = var.replication_type
  access_tier         = var.access_tier
  enable_versioning   = var.enable_versioning
  soft_delete_days    = var.soft_delete_days
  containers          = var.containers
  tags                = module.naming.tags
}

# 4. Security Groups
module "security_groups" {
  source       = "../../modules/security_groups"
  project      = var.project
  environment  = var.environment
  owner_emails = var.owners
  groups = [
    { suffix = "storage-readers", description = "Blob Data Reader access for ${var.project}-${var.name}" },
    { suffix = "storage-contributors", description = "Blob Data Contributor access for ${var.project}-${var.name}" },
  ]
}

# 5. RBAC Assignments
module "rbac" {
  source = "../../modules/rbac_assignments"
  assignments = [
    {
      principal_id         = module.security_groups.group_ids["storage-readers"]
      role_definition_name = "Storage Blob Data Reader"
      scope                = module.storage_account.id
    },
    {
      principal_id         = module.security_groups.group_ids["storage-contributors"]
      role_definition_name = "Storage Blob Data Contributor"
      scope                = module.storage_account.id
    },
  ]
}

# 6. Diagnostic Settings (optional)
module "diagnostics" {
  source = "../../modules/diagnostic_settings"
  count  = var.enable_diagnostics ? 1 : 0

  name                       = module.naming.name
  target_resource_id         = module.storage_account.id
  log_analytics_workspace_id = var.log_analytics_workspace_id
  metrics                    = ["AllMetrics"]
}
