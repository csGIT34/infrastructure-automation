# terraform/patterns/web_backend/main.tf
# Composite pattern: container_app + postgresql + key_vault
# Provisions a web backend with a Container App, PostgreSQL database, and Key Vault for secrets

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
module "naming_app" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "container_app"
  name          = var.name
  business_unit = var.business_unit
  pattern_name  = "web-backend"
}

module "naming_env" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "container_env"
  name          = var.name
  business_unit = var.business_unit
}

module "naming_pg" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "postgresql"
  name          = var.name
  business_unit = var.business_unit
}

module "naming_kv" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "keyvault"
  name          = var.name
  business_unit = var.business_unit
}

# 2. Resource Group (shared by all components)
module "resource_group" {
  source   = "../../modules/resource_group"
  name     = module.naming_app.resource_group_name
  location = var.location
  tags     = module.naming_app.tags
}

# 3. PostgreSQL
module "postgresql" {
  source                = "../../modules/postgresql"
  name                  = module.naming_pg.name
  location              = var.location
  resource_group_name   = module.resource_group.name
  postgresql_version    = var.postgresql_version
  sku_name              = var.postgresql_sku
  storage_mb            = var.postgresql_storage_mb
  backup_retention_days = var.backup_retention_days
  geo_redundant_backup  = var.geo_redundant_backup
  database_name         = var.name
  tags                  = module.naming_app.tags
}

# 4. Key Vault (stores all secrets)
module "key_vault" {
  source              = "../../modules/key_vault"
  name                = module.naming_kv.name
  location            = var.location
  resource_group_name = module.resource_group.name
  tags                = module.naming_app.tags
  secrets = {
    "database-url"      = module.postgresql.connection_string
    "pg-admin-password" = module.postgresql.admin_password
    "pg-fqdn"           = module.postgresql.fqdn
  }
}

# 5. Container App (with managed identity for Key Vault access)
module "container_app" {
  source                       = "../../modules/container_app"
  name                         = module.naming_app.name
  location                     = var.location
  resource_group_name          = module.resource_group.name
  environment_name             = module.naming_env.name
  container_image              = var.container_image
  cpu                          = var.cpu
  memory                       = var.memory
  min_replicas                 = var.min_replicas
  max_replicas                 = var.max_replicas
  enable_ingress               = true
  external_ingress             = var.external_ingress
  target_port                  = var.target_port
  enable_managed_identity      = true
  tags                         = module.naming_app.tags

  environment_variables = merge(var.environment_variables, {
    DATABASE_HOST = module.postgresql.fqdn
    DATABASE_NAME = module.postgresql.database_name
    KEY_VAULT_URI = module.key_vault.vault_uri
  })
}

# 6. RBAC: Container App managed identity -> Key Vault Secrets User
resource "azurerm_role_assignment" "app_keyvault_access" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.container_app.principal_id
}

# 7. Security Groups
module "security_groups" {
  source       = "../../modules/security_groups"
  project      = var.project
  environment  = var.environment
  owner_emails = var.owners
  groups = [
    { suffix = "backend-readers", description = "Read access to web backend ${var.project}-${var.name}" },
    { suffix = "backend-admins", description = "Admin access to web backend ${var.project}-${var.name}" },
  ]
}

# 8. RBAC Assignments (resource-scoped, not resource group-scoped)
module "rbac" {
  source = "../../modules/rbac_assignments"
  assignments = [
    # Readers get read access to individual resources
    {
      principal_id         = module.security_groups.group_ids["backend-readers"]
      role_definition_name = "Reader"
      scope                = module.container_app.id
    },
    {
      principal_id         = module.security_groups.group_ids["backend-readers"]
      role_definition_name = "Key Vault Secrets User"
      scope                = module.key_vault.id
    },
    # Admins get scoped access to individual resources
    {
      principal_id         = module.security_groups.group_ids["backend-admins"]
      role_definition_name = "Contributor"
      scope                = module.container_app.id
    },
    {
      principal_id         = module.security_groups.group_ids["backend-admins"]
      role_definition_name = "Key Vault Secrets Officer"
      scope                = module.key_vault.id
    },
    {
      principal_id         = module.security_groups.group_ids["backend-admins"]
      role_definition_name = "Reader"
      scope                = module.postgresql.id
    },
  ]
}

# 9. Diagnostic Settings (optional)
module "diagnostics_app" {
  source = "../../modules/diagnostic_settings"
  count  = var.enable_diagnostics ? 1 : 0

  name                       = "${module.naming_app.name}-app"
  target_resource_id         = module.container_app.id
  log_analytics_workspace_id = var.log_analytics_workspace_id
  logs                       = ["ContainerAppConsoleLogs", "ContainerAppSystemLogs"]
  metrics                    = ["AllMetrics"]
}

module "diagnostics_pg" {
  source = "../../modules/diagnostic_settings"
  count  = var.enable_diagnostics ? 1 : 0

  name                       = "${module.naming_app.name}-pg"
  target_resource_id         = module.postgresql.id
  log_analytics_workspace_id = var.log_analytics_workspace_id
  logs                       = ["PostgreSQLLogs"]
  metrics                    = ["AllMetrics"]
}
