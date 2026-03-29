# terraform/patterns/postgresql/main.tf
# PostgreSQL pattern: resource_group + naming + postgresql + key_vault (secrets) + security_groups + rbac

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
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}

provider "azuread" {}

# 1. Naming
module "naming_pg" {
  source           = "github.com/AzSkyLab/terraform-azurerm-naming?ref=v1.0.0"
  project          = var.project
  environment      = var.environment
  resource_type    = "postgresql"
  name             = var.name
  business_unit    = var.business_unit
  pattern_name     = "postgresql"
  application_id   = var.application_id
  application_name = var.application_name
  tier             = var.tier
  cost_center      = var.cost_center
}

module "naming_kv" {
  source           = "github.com/AzSkyLab/terraform-azurerm-naming?ref=v1.0.0"
  project          = var.project
  environment      = var.environment
  resource_type    = "keyvault"
  name             = "${var.name}-pg"
  business_unit    = var.business_unit
  application_id   = var.application_id
  application_name = var.application_name
  tier             = var.tier
  cost_center      = var.cost_center
}

# 2. Resource Group
module "resource_group" {
  source   = "github.com/AzSkyLab/terraform-azurerm-resource-group?ref=v1.0.0"
  name     = module.naming_pg.resource_group_name
  location = var.location
  tags     = module.naming_pg.tags
}

# 3. PostgreSQL
module "postgresql" {
  source                = "github.com/AzSkyLab/terraform-azurerm-postgresql?ref=v1.0.0"
  name                  = module.naming_pg.name
  location              = var.location
  resource_group_name   = module.resource_group.name
  postgresql_version    = var.postgresql_version
  sku_name              = var.sku_name
  storage_mb            = var.storage_mb
  backup_retention_days = var.backup_retention_days
  geo_redundant_backup  = var.geo_redundant_backup
  database_name         = var.name
  tags                  = module.naming_pg.tags
}

# 4. Key Vault for secrets
module "key_vault" {
  source              = "github.com/AzSkyLab/terraform-azurerm-key-vault?ref=v1.0.0"
  name                = module.naming_kv.name
  location            = var.location
  resource_group_name = module.resource_group.name
  tags                = module.naming_pg.tags
  secrets = {
    "pg-connection-string" = module.postgresql.connection_string
    "pg-admin-password"    = module.postgresql.admin_password
    "pg-fqdn"             = module.postgresql.fqdn
    "pg-database-name"    = module.postgresql.database_name
  }
}

# 5. Security Groups
module "security_groups" {
  source       = "github.com/AzSkyLab/terraform-azurerm-security-groups?ref=v1.0.0"
  project      = var.project
  environment  = var.environment
  owner_emails = var.owners
  groups = [
    { suffix = "db-readers", description = "Database read access for ${var.project}-${var.name}" },
    { suffix = "db-admins", description = "Database admin access for ${var.project}-${var.name}" },
  ]
}

# 6. RBAC Assignments
module "rbac" {
  source = "github.com/AzSkyLab/terraform-azurerm-rbac-assignments?ref=v1.0.0"
  assignments = [
    {
      principal_id         = module.security_groups.group_ids["db-readers"]
      role_definition_name = "Key Vault Secrets User"
      scope                = module.key_vault.id
    },
    {
      principal_id         = module.security_groups.group_ids["db-admins"]
      role_definition_name = "Key Vault Secrets Officer"
      scope                = module.key_vault.id
    },
  ]
}
