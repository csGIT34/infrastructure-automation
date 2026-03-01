# terraform/patterns/postgresql/main.tf
# PostgreSQL pattern: resource_group + naming + postgresql + key_vault (secrets) + security_groups + rbac + diagnostics

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
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "postgresql"
  name          = var.name
  business_unit = var.business_unit
  pattern_name  = "postgresql"
}

module "naming_kv" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "keyvault"
  name          = "${var.name}-pg"
  business_unit = var.business_unit
}

# 2. Resource Group
module "resource_group" {
  source   = "../../modules/resource_group"
  name     = module.naming_pg.resource_group_name
  location = var.location
  tags     = module.naming_pg.tags
}

# 3. PostgreSQL
module "postgresql" {
  source                = "../../modules/postgresql"
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
  source              = "../../modules/key_vault"
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
  source       = "../../modules/security_groups"
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
  source = "../../modules/rbac_assignments"
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

# 7. Diagnostic Settings (optional)
module "diagnostics" {
  source = "../../modules/diagnostic_settings"
  count  = var.enable_diagnostics ? 1 : 0

  name                       = module.naming_pg.name
  target_resource_id         = module.postgresql.id
  log_analytics_workspace_id = var.log_analytics_workspace_id
  logs                       = ["PostgreSQLLogs"]
  metrics                    = ["AllMetrics"]
}
