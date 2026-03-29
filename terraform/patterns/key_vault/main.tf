# terraform/patterns/key_vault/main.tf
# Key Vault pattern: resource_group + naming + key_vault + security_groups + rbac

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
  source           = "github.com/AzSkyLab/terraform-azurerm-naming?ref=v1.0.0"
  project          = var.project
  environment      = var.environment
  resource_type    = "keyvault"
  name             = var.name
  business_unit    = var.business_unit
  pattern_name     = "keyvault"
  application_id   = var.application_id
  application_name = var.application_name
  tier             = var.tier
  cost_center      = var.cost_center
}

# 2. Resource Group
module "resource_group" {
  source   = "github.com/AzSkyLab/terraform-azurerm-resource-group?ref=v1.0.0"
  name     = module.naming.resource_group_name
  location = var.location
  tags     = module.naming.tags
}

# 3. Key Vault
module "key_vault" {
  source                     = "github.com/AzSkyLab/terraform-azurerm-key-vault?ref=v1.0.0"
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
  source       = "github.com/AzSkyLab/terraform-azurerm-security-groups?ref=v1.0.0"
  project      = var.project
  environment  = var.environment
  owner_emails = var.owners
  groups = [
    { suffix = "secrets-readers", description = "Key Vault Secrets User access for ${var.project}-${var.name}" },
    { suffix = "secrets-admins", description = "Key Vault Secrets Officer access for ${var.project}-${var.name}" },
  ]
}

# 5. RBAC Assignments
module "rbac" {
  source = "github.com/AzSkyLab/terraform-azurerm-rbac-assignments?ref=v1.0.0"
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
