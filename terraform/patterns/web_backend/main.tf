# terraform/patterns/web_backend/main.tf
# Composite pattern: container_app + postgresql + key_vault + container_registry
# Provisions a full web backend stack

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
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
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
  source           = "github.com/AzSkyLab/terraform-azurerm-naming?ref=v1.0.0"
  project          = var.project
  environment      = var.environment
  resource_type    = "container_app"
  name             = var.name
  business_unit    = var.business_unit
  pattern_name     = "web-backend"
  application_id   = var.application_id
  application_name = var.application_name
  tier             = var.tier
  cost_center      = var.cost_center
}

module "naming_env" {
  source           = "github.com/AzSkyLab/terraform-azurerm-naming?ref=v1.0.0"
  project          = var.project
  environment      = var.environment
  resource_type    = "container_env"
  name             = var.name
  business_unit    = var.business_unit
  application_id   = var.application_id
  application_name = var.application_name
  tier             = var.tier
  cost_center      = var.cost_center
}

module "naming_pg" {
  source           = "github.com/AzSkyLab/terraform-azurerm-naming?ref=v1.0.0"
  project          = var.project
  environment      = var.environment
  resource_type    = "postgresql"
  name             = var.name
  business_unit    = var.business_unit
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
  name             = var.name
  business_unit    = var.business_unit
  application_id   = var.application_id
  application_name = var.application_name
  tier             = var.tier
  cost_center      = var.cost_center
}

module "naming_cr" {
  source           = "github.com/AzSkyLab/terraform-azurerm-naming?ref=v1.0.0"
  project          = var.project
  environment      = var.environment
  resource_type    = "container_registry"
  name             = var.name
  business_unit    = var.business_unit
  application_id   = var.application_id
  application_name = var.application_name
  tier             = var.tier
  cost_center      = var.cost_center
}

# 2. Resource Group (shared by all components)
module "resource_group" {
  source   = "github.com/AzSkyLab/terraform-azurerm-resource-group?ref=v1.0.0"
  name     = module.naming_app.resource_group_name
  location = var.location
  tags     = module.naming_app.tags
}

# 3. Container Registry
module "container_registry" {
  source              = "github.com/AzSkyLab/terraform-azurerm-container-registry?ref=v1.0.0"
  name                = module.naming_cr.name
  resource_group_name = module.resource_group.name
  location            = var.location
  sku                 = var.acr_sku
  tags                = module.naming_app.tags
}

# 4. PostgreSQL
module "postgresql" {
  source                = "github.com/AzSkyLab/terraform-azurerm-postgresql?ref=v1.0.0"
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

# 5. Key Vault (stores all secrets)
module "key_vault" {
  source              = "github.com/AzSkyLab/terraform-azurerm-key-vault?ref=v1.0.0"
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

# 6. Container App (with managed identity for Key Vault + ACR access)
module "container_app" {
  source                       = "github.com/AzSkyLab/terraform-azurerm-container-app?ref=v1.0.0"
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
    DATABASE_HOST         = module.postgresql.fqdn
    DATABASE_NAME         = module.postgresql.database_name
    KEY_VAULT_URI         = module.key_vault.vault_uri
    ACR_LOGIN_SERVER      = module.container_registry.login_server
  })
}

# 7. Wait for ARM propagation before RBAC assignments
# Azure ARM API has eventual consistency - resources may return 404
# immediately after creation when used as RBAC scopes.
resource "time_sleep" "wait_for_arm_propagation" {
  depends_on = [
    module.container_app,
    module.key_vault,
    module.postgresql,
    module.container_registry,
  ]
  create_duration = "30s"
}

# 8. RBAC: Container App managed identity -> Key Vault Secrets User
resource "azurerm_role_assignment" "app_keyvault_access" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.container_app.principal_id
  depends_on           = [time_sleep.wait_for_arm_propagation]
}

# 9. RBAC: Container App managed identity -> ACR Pull
resource "azurerm_role_assignment" "app_acr_pull" {
  scope                = module.container_registry.id
  role_definition_name = "AcrPull"
  principal_id         = module.container_app.principal_id
  depends_on           = [time_sleep.wait_for_arm_propagation]
}

# 10. Security Groups
module "security_groups" {
  source       = "github.com/AzSkyLab/terraform-azurerm-security-groups?ref=v1.0.0"
  project      = var.project
  environment  = var.environment
  owner_emails = var.owners
  groups = [
    { suffix = "backend-readers", description = "Read access to web backend ${var.project}-${var.name}" },
    { suffix = "backend-admins", description = "Admin access to web backend ${var.project}-${var.name}" },
  ]
}

# 11. RBAC Assignments (resource-scoped)
module "rbac" {
  source     = "github.com/AzSkyLab/terraform-azurerm-rbac-assignments?ref=v1.0.0"
  depends_on = [time_sleep.wait_for_arm_propagation]
  assignments = [
    # Readers
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
    {
      principal_id         = module.security_groups.group_ids["backend-readers"]
      role_definition_name = "AcrPull"
      scope                = module.container_registry.id
    },
    # Admins
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
      role_definition_name = "AcrPush"
      scope                = module.container_registry.id
    },
    {
      principal_id         = module.security_groups.group_ids["backend-admins"]
      role_definition_name = "Reader"
      scope                = module.postgresql.id
    },
  ]
}
