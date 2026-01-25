# terraform/platform/api/main.tf
# Infrastructure for the Dry Run API
#
# Provisions:
#   - Resource Group
#   - Storage Account (for Function App)
#   - App Service Plan (Flex Consumption FC1)
#   - Azure Function App (Python)
#   - Entra ID App Registrations (API + Portal)
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
# Data Sources
# -----------------------------------------------------------------------------

data "azuread_client_config" "current" {}

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

  # API identifier URI
  api_identifier_uri = "api://infra-platform-dry-run-api"
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
# Entra ID App Registration - API
# -----------------------------------------------------------------------------

resource "azuread_application" "api" {
  display_name     = "Infrastructure Platform - Dry Run API"
  identifier_uris  = [local.api_identifier_uri]
  sign_in_audience = "AzureADMyOrg"

  api {
    requested_access_token_version = 2

    # Allow Azure CLI and Azure PowerShell to get tokens for testing
    known_client_applications = [
      "04b07795-8ddb-461a-bbee-02f9e1bf7b46", # Azure CLI
      "1950a258-227b-4e31-a9cf-717495945fc2", # Azure PowerShell
    ]

    oauth2_permission_scope {
      admin_consent_description  = "Allow the application to validate infrastructure patterns"
      admin_consent_display_name = "Validate Patterns"
      enabled                    = true
      id                         = random_uuid.api_scope_id.result
      type                       = "User"
      user_consent_description   = "Allow the application to validate infrastructure patterns on your behalf"
      user_consent_display_name  = "Validate Patterns"
      value                      = "Patterns.Validate"
    }
  }

  web {
    implicit_grant {
      access_token_issuance_enabled = false
      id_token_issuance_enabled     = true
    }
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }

  tags = ["Infrastructure", "Platform", "API"]
}

resource "random_uuid" "api_scope_id" {}

resource "azuread_service_principal" "api" {
  client_id                    = azuread_application.api.client_id
  app_role_assignment_required = false

  tags = ["Infrastructure", "Platform", "API"]
}

# -----------------------------------------------------------------------------
# Entra ID App Registration - Portal (SPA)
# -----------------------------------------------------------------------------

resource "azuread_application" "portal" {
  display_name     = "Infrastructure Platform - Portal"
  sign_in_audience = "AzureADMyOrg"

  single_page_application {
    redirect_uris = var.portal_redirect_uris
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Scope"
    }
  }

  # Permission to call the Dry Run API
  required_resource_access {
    resource_app_id = azuread_application.api.client_id

    resource_access {
      id   = random_uuid.api_scope_id.result # Patterns.Validate scope
      type = "Scope"
    }
  }

  tags = ["Infrastructure", "Platform", "Portal"]
}

resource "azuread_service_principal" "portal" {
  client_id                    = azuread_application.portal.client_id
  app_role_assignment_required = false

  tags = ["Infrastructure", "Platform", "Portal"]
}

# Pre-authorize the portal to call the API (no consent prompt)
resource "azuread_application_pre_authorized" "portal_to_api" {
  application_id       = azuread_application.api.id
  authorized_client_id = azuread_application.portal.client_id
  permission_ids       = [random_uuid.api_scope_id.result]
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

  site_config {
    cors {
      allowed_origins     = var.cors_allowed_origins
      support_credentials = true
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # ---------------------------------------------------------------------------
  # Entra ID Authentication
  # ---------------------------------------------------------------------------
  auth_settings_v2 {
    auth_enabled           = true
    require_authentication = true
    unauthenticated_action = "Return401"

    active_directory_v2 {
      client_id            = azuread_application.api.client_id
      tenant_auth_endpoint = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/v2.0"
      allowed_audiences    = [local.api_identifier_uri, azuread_application.api.client_id]
    }

    login {
      token_store_enabled = true
    }
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

output "entra_auth" {
  description = "Entra ID authentication configuration"
  value = {
    tenant_id         = data.azuread_client_config.current.tenant_id
    api_client_id     = azuread_application.api.client_id
    api_scope         = "${local.api_identifier_uri}/Patterns.Validate"
    portal_client_id  = azuread_application.portal.client_id
    authority         = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}"
  }
}

output "portal_msal_config" {
  description = "MSAL configuration for portal integration (copy to portal JavaScript)"
  value       = <<-EOT
    // MSAL Configuration for Portal
    const msalConfig = {
      auth: {
        clientId: "${azuread_application.portal.client_id}",
        authority: "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}",
        redirectUri: window.location.origin
      },
      cache: {
        cacheLocation: "sessionStorage",
        storeAuthStateInCookie: false
      }
    };

    const apiConfig = {
      endpoint: "https://${azurerm_function_app_flex_consumption.api.default_hostname}/api/dry-run",
      scopes: ["${local.api_identifier_uri}/Patterns.Validate"]
    };
  EOT
}

output "deployment_instructions" {
  description = "Instructions for deploying the API"
  value       = <<-EOT
    Dry Run API Infrastructure Provisioned!

    Function App: ${azurerm_function_app_flex_consumption.api.name}
    API Endpoint: https://${azurerm_function_app_flex_consumption.api.default_hostname}/api/dry-run

    AUTHENTICATION:
    The API now uses Entra ID authentication (no more API keys needed).

    Portal Client ID: ${azuread_application.portal.client_id}
    API Scope: ${local.api_identifier_uri}/Patterns.Validate
    Authority: https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}

    To deploy the function code:
    1. Navigate to terraform/platform/api/functions
    2. Run: func azure functionapp publish ${azurerm_function_app_flex_consumption.api.name}

    Security Groups:
    - API Users: ${module.security_groups.group_names["api-users"]}
    - API Admins: ${module.security_groups.group_names["api-admins"]}
  EOT
}
