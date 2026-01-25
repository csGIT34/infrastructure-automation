# Test fixture: Static Site pattern
#
# Tests Static Web App + Security Groups + RBAC + Access Reviews

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
  name          = "web"
  business_unit = "engineering"
  pattern_name  = "static-site"
}

# Resource Group
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

# Static Web App
module "swa_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "static_web_app"
  name          = local.name
  business_unit = local.business_unit
}

module "static_web_app" {
  source = "../../../../modules/static-web-app"

  name                = module.swa_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku_tier        = "Free"
    sku_size        = "Free"
    repository_url  = ""
    branch          = "main"
    app_location    = "/"
    api_location    = ""
    output_location = "build"
  }
  tags = module.naming.tags
}

# Security Groups
module "security_groups" {
  source = "../../../../modules/security-groups"

  project     = local.project
  environment = local.environment
  groups = [
    {
      suffix      = "swa-developers"
      description = "Developers for ${local.name} static site (test)"
    },
    {
      suffix      = "swa-admins"
      description = "Administrators for ${local.name} static site (test)"
    }
  ]
  # Only pass owner_emails if owner_email is set, otherwise empty list
  owner_emails = var.owner_email != "" ? [var.owner_email] : []
}

# RBAC Assignments
module "rbac" {
  source = "../../../../modules/rbac-assignments"

  assignments = [
    {
      principal_id         = module.security_groups.group_ids["swa-developers"]
      role_definition_name = "Reader"
      scope                = module.static_web_app.id
      description          = "Developers - read access to static web app (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["swa-admins"]
      role_definition_name = "Contributor"
      scope                = module.static_web_app.id
      description          = "Admins - full access to static web app (test)"
    }
  ]
}

# Access Reviews for Security Groups
module "access_review_developers" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["swa-developers"]
  group_name = module.security_groups.group_names["swa-developers"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

module "access_review_admins" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["swa-admins"]
  group_name = module.security_groups.group_names["swa-admins"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

# Outputs
output "static_web_app" {
  value = {
    name         = module.static_web_app.name
    default_url  = module.static_web_app.default_host_name
    id           = module.static_web_app.id
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
    Static Site Pattern Test Results
    =================================

    Static Web App:
    - Name: ${module.static_web_app.name}
    - URL: https://${module.static_web_app.default_host_name}

    Security Groups:
    - Developers: ${module.security_groups.group_names["swa-developers"]}
    - Admins: ${module.security_groups.group_names["swa-admins"]}

    Access Reviews:
    - ${module.access_review_developers.review_name}
    - ${module.access_review_admins.review_name}

    Deploy with SWA CLI:
      swa deploy ./build --deployment-token <token>
  EOT
}
