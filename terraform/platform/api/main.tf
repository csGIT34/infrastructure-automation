# terraform/platform/api/main.tf
# Infrastructure for the Dry Run API
#
# Provisions:
#   - Resource Group
#   - Storage Account (for Function App)
#   - App Service Plan (Consumption/Y1)
#   - Azure Function App (Python)
#   - Security Groups (api-users, api-admins)
#   - RBAC Assignments

terraform {
  required_version = ">= 1.5.0"
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

  backend "azurerm" {
    use_oidc = true
  }
}

provider "azurerm" {
  features {}
  use_oidc        = true
  subscription_id = var.subscription_id
}

provider "azuread" {
  use_oidc = true
}

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  tags = {
    Project      = var.project
    Environment  = var.environment
    BusinessUnit = var.business_unit
    ManagedBy    = "Terraform-Platform"
  }
}

# -----------------------------------------------------------------------------
# Naming
# -----------------------------------------------------------------------------

module "naming" {
  source = "../../modules/naming"

  project       = var.project
  environment   = var.environment
  resource_type = "resource_group"
  name          = "api"
  business_unit = var.business_unit
}

module "func_naming" {
  source = "../../modules/naming"

  project       = var.project
  environment   = var.environment
  resource_type = "function_app"
  name          = "dryrun"
  business_unit = var.business_unit
}

# -----------------------------------------------------------------------------
# Random suffix for storage account uniqueness
# -----------------------------------------------------------------------------

resource "random_string" "storage_suffix" {
  length  = 8
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "api" {
  name     = module.naming.resource_group_name
  location = var.location
  tags     = local.tags
}

# -----------------------------------------------------------------------------
# Storage Account (required for Function App)
# -----------------------------------------------------------------------------

resource "azurerm_storage_account" "func" {
  name                     = "stfuncapi${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.api.name
  location                 = azurerm_resource_group.api.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Blob Container for Flex Consumption deployments
# -----------------------------------------------------------------------------

resource "azurerm_storage_container" "deployments" {
  name                  = "deployments"
  storage_account_id    = azurerm_storage_account.func.id
  container_access_type = "private"
}

# -----------------------------------------------------------------------------
# App Service Plan (Flex Consumption FC1 - no VM quota required)
# -----------------------------------------------------------------------------

resource "azurerm_service_plan" "func" {
  name                = "asp-${var.project}-api-${var.environment}"
  resource_group_name = azurerm_resource_group.api.name
  location            = azurerm_resource_group.api.location
  os_type             = "Linux"
  sku_name            = "FC1"

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Function App (Flex Consumption)
# -----------------------------------------------------------------------------

resource "azurerm_function_app_flex_consumption" "api" {
  name                = module.func_naming.name
  resource_group_name = azurerm_resource_group.api.name
  location            = azurerm_resource_group.api.location
  service_plan_id     = azurerm_service_plan.func.id

  storage_container_type      = "blobContainer"
  storage_container_endpoint  = "${azurerm_storage_account.func.primary_blob_endpoint}${azurerm_storage_container.deployments.name}"
  storage_authentication_type = "StorageAccountConnectionString"
  storage_access_key          = azurerm_storage_account.func.primary_access_key

  runtime_name           = "python"
  runtime_version        = "3.11"
  maximum_instance_count = 40
  instance_memory_in_mb  = 2048

  site_config {}

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
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
      suffix      = "api-users"
      description = "Users who can call the Dry Run API"
    },
    {
      suffix      = "api-admins"
      description = "Administrators with full API access"
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
      principal_id         = module.security_groups.group_ids["api-users"]
      role_definition_name = "Reader"
      scope                = azurerm_resource_group.api.id
      description          = "API users - read access to resources"
    },
    {
      principal_id         = module.security_groups.group_ids["api-admins"]
      role_definition_name = "Contributor"
      scope                = azurerm_resource_group.api.id
      description          = "API admins - manage API resources"
    },
    {
      principal_id         = module.security_groups.group_ids["api-admins"]
      role_definition_name = "Contributor"
      scope                = azurerm_function_app_flex_consumption.api.id
      description          = "API admins - manage Function App"
    }
  ]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "resource_group" {
  description = "Resource group name"
  value       = azurerm_resource_group.api.name
}

output "function_app" {
  description = "Function App details"
  value = {
    name     = azurerm_function_app_flex_consumption.api.name
    url      = "https://${azurerm_function_app_flex_consumption.api.default_hostname}"
    hostname = azurerm_function_app_flex_consumption.api.default_hostname
  }
}

output "api_endpoint" {
  description = "Dry Run API endpoint"
  value       = "https://${azurerm_function_app_flex_consumption.api.default_hostname}/api/dry-run"
}

output "function_app_principal_id" {
  description = "Function App managed identity principal ID"
  value       = azurerm_function_app_flex_consumption.api.identity[0].principal_id
}

output "security_groups" {
  description = "Security group names"
  value       = module.security_groups.group_names
}

output "storage_account" {
  description = "Storage account name"
  value       = azurerm_storage_account.func.name
}

output "deployment_instructions" {
  description = "Instructions for deploying the API"
  value       = <<-EOT
    Dry Run API Infrastructure Provisioned!

    Function App: ${azurerm_function_app_flex_consumption.api.name}
    API Endpoint: https://${azurerm_function_app_flex_consumption.api.default_hostname}/api/dry-run

    To deploy the function code:
    1. Navigate to terraform/platform/api/functions
    2. Run: func azure functionapp publish ${azurerm_function_app_flex_consumption.api.name}

    Or use GitHub Actions:
    - The workflow will automatically deploy on push to main

    To get the function key (for API auth):
    - az functionapp keys list -g ${azurerm_resource_group.api.name} -n ${azurerm_function_app_flex_consumption.api.name}

    Security Groups:
    - API Users: ${module.security_groups.group_names["api-users"]}
    - API Admins: ${module.security_groups.group_names["api-admins"]}
  EOT
}
