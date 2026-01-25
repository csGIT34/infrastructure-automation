# Test fixture: Web-app pattern
#
# Replicates the web-app pattern composition for testing.
# Web-app is a composite pattern: Static Web App + Function App + PostgreSQL + Key Vault

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

variable "resource_suffix" {
  type = string
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "owner_email" {
  description = "Owner email for security groups (optional for tests)"
  type        = string
  default     = ""
}

locals {
  project       = "tftest-${var.resource_suffix}"
  environment   = "dev"
  name          = "webapp"
  business_unit = "engineering"
  pattern_name  = "web-app"
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------
module "naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "resource_group"
  name          = local.name
  business_unit = local.business_unit
  pattern_name  = local.pattern_name
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
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "static_web_app"
  name          = "${local.name}-frontend"
  business_unit = local.business_unit
}

module "static_web_app" {
  source = "../../../../modules/static-web-app"

  name                = module.swa_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  config = {
    sku_tier = "Free"
    sku_size = "Free"
  }
  tags = module.naming.tags
}

# -----------------------------------------------------------------------------
# Function App (Backend API)
# -----------------------------------------------------------------------------
module "func_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "function_app"
  name          = "${local.name}-api"
  business_unit = local.business_unit
}

module "function_app" {
  source = "../../../../modules/function-app"

  name                = module.func_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku             = "FC1"  # Flex Consumption - no VM quota required
    runtime         = "python"
    runtime_version = "3.11"
    os_type         = "Linux"
    cors_origins    = ["https://${module.static_web_app.default_host_name}"]
  }
  tags = module.naming.tags
}

# -----------------------------------------------------------------------------
# PostgreSQL Database
# -----------------------------------------------------------------------------
module "db_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "postgresql"
  name          = "${local.name}-db"
  business_unit = local.business_unit
}

module "postgresql" {
  source = "../../../../modules/postgresql"

  name                = module.db_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku = "B_Standard_B1ms"
  }
  tags = module.naming.tags
}

# -----------------------------------------------------------------------------
# Key Vault (Shared secrets)
# -----------------------------------------------------------------------------
module "keyvault_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "keyvault"
  name          = local.name
  business_unit = local.business_unit
  pattern_name  = local.pattern_name
}

locals {
  db_secrets = {
    "db-connection-string" = "Host=${module.postgresql.server_fqdn};Database=${module.postgresql.database_name};Username=psqladmin"
    "db-server-fqdn"       = module.postgresql.server_fqdn
  }
}

module "keyvault" {
  source = "../../../../modules/keyvault"

  name                = module.keyvault_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku            = "standard"
    rbac_enabled   = true
    default_action = "Allow"
  }
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
  source = "../../../../modules/security-groups"

  project     = local.project
  environment = local.environment
  groups = [
    {
      suffix      = "webapp-developers"
      description = "Developers for ${local.name} web app (test)"
    },
    {
      suffix      = "webapp-admins"
      description = "Administrators for ${local.name} web app (test)"
    }
  ]
  # Only pass owner_emails if owner_email is set, otherwise empty list
  owner_emails = var.owner_email != "" ? [var.owner_email] : []
}

# -----------------------------------------------------------------------------
# RBAC Assignments
# -----------------------------------------------------------------------------
module "rbac" {
  source = "../../../../modules/rbac-assignments"

  assignments = [
    {
      principal_id         = module.security_groups.group_ids["webapp-developers"]
      role_definition_name = "Website Contributor"
      scope                = module.function_app.id
      description          = "Deploy to API function (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["webapp-admins"]
      role_definition_name = "Key Vault Secrets Officer"
      scope                = module.keyvault.vault_id
      description          = "Manage app secrets (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["webapp-admins"]
      role_definition_name = "Contributor"
      scope                = module.postgresql.server_id
      description          = "Manage PostgreSQL server (test)"
    }
  ]
}

# -----------------------------------------------------------------------------
# Access Reviews for Security Groups
# -----------------------------------------------------------------------------
module "access_review_developers" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["webapp-developers"]
  group_name = module.security_groups.group_names["webapp-developers"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

module "access_review_admins" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["webapp-admins"]
  group_name = module.security_groups.group_names["webapp-admins"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "frontend" {
  value = {
    name = module.static_web_app.name
    url  = "https://${module.static_web_app.default_host_name}"
  }
}

output "api" {
  value = {
    name = module.function_app.name
    url  = module.function_app.url
  }
}

output "database" {
  value = {
    type   = "postgresql"
    server = module.postgresql.server_fqdn
    name   = module.postgresql.database_name
  }
}

output "keyvault" {
  value = {
    name = module.keyvault.vault_name
    uri  = module.keyvault.vault_uri
    id   = module.keyvault.vault_id
  }
}

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "security_groups" {
  value = module.security_groups.group_names
}

output "access_reviews" {
  value = {
    developers = module.access_review_developers.review_name
    admins     = module.access_review_admins.review_name
  }
}

output "access_info" {
  value = <<-EOT
    Web App: ${local.name}

    Frontend: https://${module.static_web_app.default_host_name}
    API: ${module.function_app.url}
    Database: ${module.postgresql.server_fqdn}

    Key Vault: ${module.keyvault.vault_name}

    Security Groups:
    - Developers: ${module.security_groups.group_names["webapp-developers"]}
    - Admins: ${module.security_groups.group_names["webapp-admins"]}

    Access Reviews:
    - ${module.access_review_developers.review_name}
    - ${module.access_review_admins.review_name}
  EOT
}
