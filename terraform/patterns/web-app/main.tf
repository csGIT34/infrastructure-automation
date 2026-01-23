# terraform/patterns/web-app/main.tf
# Web App Pattern - Static frontend + Function backend + Database
# Composite pattern combining multiple resources

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.0" }
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

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------
variable "project" { type = string }
variable "environment" { type = string }
variable "name" { type = string }
variable "owners" { type = list(string) }
variable "business_unit" { type = string }
variable "location" { type = string default = "eastus" }

# Database selection
variable "database_type" {
  description = "Database type: postgresql, azure_sql, or none"
  type        = string
  default     = "postgresql"
}

# Sizing-resolved configs
variable "function_sku" { type = string default = "Y1" }
variable "db_sku" { type = string default = "B_Standard_B1ms" }
variable "swa_sku_tier" { type = string default = "Free" }

# Pattern-specific
variable "runtime" { type = string default = "python" }
variable "runtime_version" { type = string default = "3.11" }
variable "enable_diagnostics" { type = bool default = false }
variable "log_analytics_workspace_id" { type = string default = "" }

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
}

resource "azurerm_resource_group" "main" {
  name     = module.naming.resource_group_name
  location = var.location
  tags     = module.naming.tags
}

# -----------------------------------------------------------------------------
# Static Web App (Frontend)
# -----------------------------------------------------------------------------
module "swa_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "static_web_app"
  name          = "${var.name}-frontend"
  business_unit = var.business_unit
}

module "static_web_app" {
  source = "../../modules/static-web-app"

  name                = module.swa_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  config = {
    sku_tier = var.swa_sku_tier
    sku_size = var.swa_sku_tier
  }
  tags = module.naming.tags
}

# -----------------------------------------------------------------------------
# Function App (Backend API)
# -----------------------------------------------------------------------------
module "func_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "function_app"
  name          = "${var.name}-api"
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
    cors_origins    = ["https://${module.static_web_app.default_hostname}"]
  }
  tags = module.naming.tags
}

# -----------------------------------------------------------------------------
# Database (optional)
# -----------------------------------------------------------------------------
module "db_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = var.database_type == "postgresql" ? "postgresql" : "azure_sql"
  name          = "${var.name}-db"
  business_unit = var.business_unit
}

module "postgresql" {
  source = "../../modules/postgresql"
  count  = var.database_type == "postgresql" ? 1 : 0

  name                = module.db_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = { sku = var.db_sku }
  tags = module.naming.tags
}

module "azure_sql" {
  source = "../../modules/azure-sql"
  count  = var.database_type == "azure_sql" ? 1 : 0

  name                = module.db_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = { sku_name = var.db_sku == "B_Standard_B1ms" ? "Basic" : var.db_sku }
  tags = module.naming.tags
}

# -----------------------------------------------------------------------------
# Key Vault (Shared secrets)
# -----------------------------------------------------------------------------
module "keyvault_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "keyvault"
  name          = var.name
  business_unit = var.business_unit
}

locals {
  db_secrets = var.database_type == "postgresql" ? {
    "db-connection-string" = "Host=${module.postgresql[0].server_fqdn};Database=${module.postgresql[0].database_name};Username=psqladmin"
    "db-server-fqdn"       = module.postgresql[0].server_fqdn
  } : var.database_type == "azure_sql" ? module.azure_sql[0].secrets_for_keyvault : {}
}

module "keyvault" {
  source = "../../modules/keyvault"

  name                = module.keyvault_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = { sku = "standard", rbac_enabled = true }
  secrets = merge(
    module.function_app.secrets_for_keyvault,
    local.db_secrets
  )
  secrets_user_principal_ids = {
    "api" = module.function_app.principal_id
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
    { suffix = "webapp-developers", description = "Developers for ${var.name} web app" },
    { suffix = "webapp-admins", description = "Administrators for ${var.name} web app" }
  ]
  owner_emails = var.owners
}

# -----------------------------------------------------------------------------
# RBAC Assignments
# -----------------------------------------------------------------------------
module "rbac" {
  source = "../../modules/rbac-assignments"
  assignments = concat(
    [
      {
        principal_id         = module.security_groups.group_ids["webapp-developers"]
        role_definition_name = "Website Contributor"
        scope                = module.function_app.id
        description          = "Deploy to API function"
      },
      {
        principal_id         = module.security_groups.group_ids["webapp-admins"]
        role_definition_name = "Key Vault Secrets Officer"
        scope                = module.keyvault.vault_id
        description          = "Manage app secrets"
      }
    ],
    var.database_type == "postgresql" ? [
      {
        principal_id         = module.security_groups.group_ids["webapp-admins"]
        role_definition_name = "Contributor"
        scope                = module.postgresql[0].server_id
        description          = "Manage PostgreSQL server"
      }
    ] : [],
    var.database_type == "azure_sql" ? [
      {
        principal_id         = module.security_groups.group_ids["webapp-admins"]
        role_definition_name = "SQL DB Contributor"
        scope                = module.azure_sql[0].database_id
        description          = "Manage SQL database"
      }
    ] : []
  )
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "frontend" {
  value = {
    name = module.static_web_app.name
    url  = "https://${module.static_web_app.default_hostname}"
  }
}

output "api" {
  value = {
    name = module.function_app.name
    url  = module.function_app.url
  }
}

output "database" {
  value = var.database_type == "postgresql" ? {
    type   = "postgresql"
    server = module.postgresql[0].server_fqdn
    name   = module.postgresql[0].database_name
  } : var.database_type == "azure_sql" ? {
    type   = "azure_sql"
    server = module.azure_sql[0].server_fqdn
    name   = module.azure_sql[0].database_name
  } : null
}

output "keyvault" {
  value = { name = module.keyvault.vault_name, uri = module.keyvault.vault_uri }
}

output "resource_group" { value = azurerm_resource_group.main.name }
output "security_groups" { value = module.security_groups.group_names }

output "access_info" {
  value = <<-EOT
    Web App: ${var.name}

    Frontend: https://${module.static_web_app.default_hostname}
    API: ${module.function_app.url}
    ${var.database_type != "none" ? "Database: ${var.database_type == "postgresql" ? module.postgresql[0].server_fqdn : module.azure_sql[0].server_fqdn}" : ""}

    Key Vault: ${module.keyvault.vault_name}

    Security Groups:
    - Developers: ${module.security_groups.group_names["webapp-developers"]}
    - Admins: ${module.security_groups.group_names["webapp-admins"]}
  EOT
}
