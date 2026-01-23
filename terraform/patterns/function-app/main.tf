# terraform/patterns/function-app/main.tf
# Function App Pattern - Serverless Azure Functions with managed identity

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
  backend "azurerm" {
    use_oidc = true
  }
}

provider "azurerm" {
  features {}
  use_oidc = true
}

provider "azuread" {
  use_oidc = true
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------
variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "name" {
  description = "Function app name"
  type        = string
}

variable "owners" {
  description = "List of owner email addresses"
  type        = list(string)
}

variable "business_unit" {
  description = "Business unit for tagging"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

# Sizing-resolved config
variable "sku" {
  description = "App Service Plan SKU (Y1, B1, S1, P1v2, etc.)"
  type        = string
  default     = "Y1"
}

variable "runtime" {
  description = "Function runtime (python, node, dotnet, java)"
  type        = string
  default     = "python"
}

variable "runtime_version" {
  description = "Runtime version"
  type        = string
  default     = "3.11"
}

variable "os_type" {
  description = "Operating system (Linux or Windows)"
  type        = string
  default     = "Linux"
}

# Pattern-specific config
variable "app_settings" {
  description = "Additional app settings"
  type        = map(string)
  default     = {}
}

variable "cors_origins" {
  description = "Allowed CORS origins"
  type        = list(string)
  default     = []
}

variable "enable_diagnostics" {
  description = "Enable diagnostic settings"
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------
module "naming" {
  source = "../../modules/naming"

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
# Function App (base module)
# -----------------------------------------------------------------------------
module "function_naming" {
  source = "../../modules/naming"

  project       = var.project
  environment   = var.environment
  resource_type = "function_app"
  name          = var.name
  business_unit = var.business_unit
}

module "function_app" {
  source = "../../modules/function-app"

  name                = module.function_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku             = var.sku
    runtime         = var.runtime
    runtime_version = var.runtime_version
    os_type         = var.os_type
    app_settings    = var.app_settings
    cors_origins    = length(var.cors_origins) > 0 ? var.cors_origins : ["*"]
  }
  tags = module.naming.tags
}

# -----------------------------------------------------------------------------
# Key Vault for secrets
# -----------------------------------------------------------------------------
module "keyvault_naming" {
  source = "../../modules/naming"

  project       = var.project
  environment   = var.environment
  resource_type = "keyvault"
  name          = var.name
  business_unit = var.business_unit
}

module "keyvault" {
  source = "../../modules/keyvault"

  name                = module.keyvault_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku          = "standard"
    rbac_enabled = true
  }
  secrets = module.function_app.secrets_for_keyvault
  secrets_user_principal_ids = {
    (var.name) = module.function_app.principal_id
  }
  tags = module.naming.tags
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
module "security_groups" {
  source = "../../modules/security-groups"

  project     = var.project
  environment = var.environment
  groups = [
    {
      suffix      = "func-developers"
      description = "Developers for ${var.name} function app"
    },
    {
      suffix      = "func-admins"
      description = "Administrators for ${var.name} function app"
    }
  ]
  owner_emails = var.owners
}

# -----------------------------------------------------------------------------
# RBAC Assignments
# -----------------------------------------------------------------------------
module "rbac" {
  source = "../../modules/rbac-assignments"

  assignments = [
    {
      principal_id         = module.security_groups.group_ids["func-developers"]
      role_definition_name = "Website Contributor"
      scope                = module.function_app.id
      description          = "Function developers - deploy access"
    },
    {
      principal_id         = module.security_groups.group_ids["func-admins"]
      role_definition_name = "Website Contributor"
      scope                = module.function_app.id
      description          = "Function admins - full access"
    },
    {
      principal_id         = module.security_groups.group_ids["func-admins"]
      role_definition_name = "Key Vault Secrets Officer"
      scope                = module.keyvault.vault_id
      description          = "Function admins - secrets management"
    }
  ]
}

# -----------------------------------------------------------------------------
# Diagnostic Settings
# -----------------------------------------------------------------------------
module "diagnostics" {
  source = "../../modules/diagnostic-settings"
  count  = var.enable_diagnostics && var.log_analytics_workspace_id != "" ? 1 : 0

  name                       = module.function_naming.name
  target_resource_id         = module.function_app.id
  log_analytics_workspace_id = var.log_analytics_workspace_id
  logs                       = ["FunctionAppLogs"]
  metrics                    = ["AllMetrics"]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "function_app" {
  description = "Function app details"
  value = {
    name         = module.function_app.name
    url          = module.function_app.url
    id           = module.function_app.id
    principal_id = module.function_app.principal_id
  }
}

output "keyvault" {
  description = "Key Vault for secrets"
  value = {
    name = module.keyvault.vault_name
    uri  = module.keyvault.vault_uri
  }
}

output "resource_group" {
  description = "Resource group name"
  value       = azurerm_resource_group.main.name
}

output "security_groups" {
  description = "Security group names"
  value       = module.security_groups.group_names
}

output "access_info" {
  description = "Access information for developers"
  value       = <<-EOT
    Function App: ${module.function_app.name}
    URL: ${module.function_app.url}

    Key Vault: ${module.keyvault.vault_name}
    Managed Identity: ${module.function_app.principal_id}

    Security Groups:
    - Developers: ${module.security_groups.group_names["func-developers"]}
    - Admins: ${module.security_groups.group_names["func-admins"]}

    Deploy with Azure Functions Core Tools:
      func azure functionapp publish ${module.function_app.name}
  EOT
}
