# terraform/patterns/static-site/main.tf
# Static Site Pattern - Azure Static Web Apps for SPAs and JAMstack

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = ">= 4.0" }
    azuread = { source = "hashicorp/azuread", version = "~> 2.0" }
  }
  backend "azurerm" { use_oidc = true }
}

provider "azurerm" {
  features {}
  use_oidc = true
}
provider "azuread" { use_oidc = true }

# Variables
variable "project" { type = string }
variable "environment" { type = string }
variable "name" { type = string }
variable "owners" { type = list(string) }
variable "business_unit" { type = string }
variable "location" {
  type    = string
  default = "eastus2"
}

# Sizing-resolved
variable "sku_tier" {
  type    = string
  default = "Free"
}
variable "sku_size" {
  type    = string
  default = "Free"
}

# Pattern-specific
variable "repository_url" {
  type    = string
  default = ""
}
variable "branch" {
  type    = string
  default = "main"
}
variable "app_location" {
  type    = string
  default = "/"
}
variable "api_location" {
  type    = string
  default = ""
}
variable "output_location" {
  type    = string
  default = "build"
}

variable "enable_diagnostics" {
  type    = bool
  default = false
}
variable "enable_access_review" {
  type    = bool
  default = false
}
variable "purge_protection" {
  type    = bool
  default = false
}
variable "geo_redundant_backup" {
  type    = bool
  default = false
}
variable "access_reviewers" {
  type    = list(string)
  default = []
}
variable "log_analytics_workspace_id" {
  type    = string
  default = ""
}

# Resource Group
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

# Static Web App
module "swa_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "static_web_app"
  name          = var.name
  business_unit = var.business_unit
}

module "static_web_app" {
  source = "../../modules/static-web-app"

  name                = module.swa_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku_tier        = var.sku_tier
    sku_size        = var.sku_size
    repository_url  = var.repository_url
    branch          = var.branch
    app_location    = var.app_location
    api_location    = var.api_location
    output_location = var.output_location
  }
  tags = module.naming.tags
}

# Security Groups
module "security_groups" {
  source       = "../../modules/security-groups"
  project      = var.project
  environment  = var.environment
  groups = [
    { suffix = "swa-developers", description = "Developers for ${var.name} static site" },
    { suffix = "swa-admins", description = "Administrators for ${var.name} static site" }
  ]
  owner_emails = var.owners
}

# RBAC
module "rbac" {
  source = "../../modules/rbac-assignments"
  assignments = [
    {
      principal_id         = module.security_groups.group_ids["swa-developers"]
      role_definition_name = "Reader"
      scope                = module.static_web_app.id
    },
    {
      principal_id         = module.security_groups.group_ids["swa-admins"]
      role_definition_name = "Contributor"
      scope                = module.static_web_app.id
    }
  ]
}

# Access Review (prod only)
module "access_review" {
  source = "../../modules/access-review"
  count  = var.enable_access_review && length(var.access_reviewers) > 0 ? 1 : 0

  group_id        = module.security_groups.group_ids["swa-admins"]
  group_name      = module.security_groups.group_names["swa-admins"]
  reviewer_emails = var.access_reviewers
  frequency       = "quarterly"
}

# Outputs
output "static_web_app" {
  value = {
    name        = module.static_web_app.name
    default_url = module.static_web_app.default_hostname
    id          = module.static_web_app.id
  }
}
output "resource_group" { value = azurerm_resource_group.main.name }
output "security_groups" { value = module.security_groups.group_names }
output "access_info" {
  value = <<-EOT
    Static Web App: ${module.static_web_app.name}
    URL: https://${module.static_web_app.default_hostname}

    Security Groups:
    - Developers: ${module.security_groups.group_names["swa-developers"]}
    - Admins: ${module.security_groups.group_names["swa-admins"]}

    Deploy with SWA CLI:
      swa deploy ./build --deployment-token <token>
  EOT
}
