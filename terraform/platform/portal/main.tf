# terraform/platform/portal/main.tf
# Infrastructure for the Self-Service Portal
#
# Provisions:
#   - Resource Group
#   - Azure Static Web App
#   - Security Groups (developers, admins)
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
# Variables
# -----------------------------------------------------------------------------

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "infra-portal"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus2"
}

variable "business_unit" {
  description = "Business unit for tagging"
  type        = string
  default     = "platform"
}

variable "owners" {
  description = "Email addresses of portal owners"
  type        = list(string)
  default     = []
}

variable "sku_tier" {
  description = "Static Web App SKU tier (Free or Standard)"
  type        = string
  default     = "Free"
}

variable "sku_size" {
  description = "Static Web App SKU size (Free or Standard)"
  type        = string
  default     = "Free"
}

# -----------------------------------------------------------------------------
# Naming
# -----------------------------------------------------------------------------

module "naming" {
  source = "../../modules/naming"

  project       = var.project
  environment   = var.environment
  resource_type = "resource_group"
  name          = "portal"
  business_unit = var.business_unit
}

module "swa_naming" {
  source = "../../modules/naming"

  project       = var.project
  environment   = var.environment
  resource_type = "static_web_app"
  name          = "portal"
  business_unit = var.business_unit
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "portal" {
  name     = module.naming.resource_group_name
  location = var.location
  tags     = module.naming.tags
}

# -----------------------------------------------------------------------------
# Static Web App
# -----------------------------------------------------------------------------

module "static_web_app" {
  source = "../../modules/static-web-app"

  name                = module.swa_naming.name
  resource_group_name = azurerm_resource_group.portal.name
  location            = azurerm_resource_group.portal.location

  config = {
    sku_tier = var.sku_tier
    sku_size = var.sku_size
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
      suffix      = "portal-developers"
      description = "Developers who can view portal resources"
    },
    {
      suffix      = "portal-admins"
      description = "Administrators with full portal access"
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
      principal_id         = module.security_groups.group_ids["portal-developers"]
      role_definition_name = "Reader"
      scope                = azurerm_resource_group.portal.id
      description          = "Portal developers - read access to resources"
    },
    {
      principal_id         = module.security_groups.group_ids["portal-admins"]
      role_definition_name = "Contributor"
      scope                = azurerm_resource_group.portal.id
      description          = "Portal admins - manage portal resources"
    },
    {
      principal_id         = module.security_groups.group_ids["portal-admins"]
      role_definition_name = "Contributor"
      scope                = module.static_web_app.id
      description          = "Portal admins - manage Static Web App"
    }
  ]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "resource_group" {
  description = "Resource group name"
  value       = azurerm_resource_group.portal.name
}

output "static_web_app" {
  description = "Static Web App details"
  value = {
    name     = module.static_web_app.name
    url      = "https://${module.static_web_app.default_host_name}"
    hostname = module.static_web_app.default_host_name
  }
}

output "static_web_app_api_key" {
  description = "Static Web App deployment API key (use as AZURE_STATIC_WEB_APPS_TOKEN secret)"
  value       = module.static_web_app.api_key
  sensitive   = true
}

output "security_groups" {
  description = "Security group names"
  value       = module.security_groups.group_names
}

output "deployment_instructions" {
  description = "Instructions for deploying the portal"
  value       = <<-EOT
    Portal Infrastructure Provisioned!

    Static Web App: ${module.static_web_app.name}
    URL: https://${module.static_web_app.default_host_name}

    To deploy the portal:
    1. Get the API key:
       terraform output -raw static_web_app_api_key

    2. Add as GitHub secret:
       AZURE_STATIC_WEB_APPS_TOKEN = <api_key>

    3. Push changes to trigger deployment

    Security Groups:
    - Developers: ${module.security_groups.group_names["portal-developers"]}
    - Admins: ${module.security_groups.group_names["portal-admins"]}
  EOT
}
