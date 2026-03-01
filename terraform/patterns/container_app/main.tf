# terraform/patterns/container_app/main.tf
# Container App pattern: resource_group + naming + container_app + security_groups + rbac + diagnostics

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
  pattern_name  = "container-app"
}

module "naming_env" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "container_env"
  name          = var.name
  business_unit = var.business_unit
}

# 2. Resource Group
module "resource_group" {
  source   = "../../modules/resource_group"
  name     = module.naming_app.resource_group_name
  location = var.location
  tags     = module.naming_app.tags
}

# 3. Container App
module "container_app" {
  source                       = "../../modules/container_app"
  name                         = module.naming_app.name
  location                     = var.location
  resource_group_name          = module.resource_group.name
  container_app_environment_id = var.container_app_environment_id
  environment_name             = module.naming_env.name
  container_image              = var.container_image
  cpu                          = var.cpu
  memory                       = var.memory
  min_replicas                 = var.min_replicas
  max_replicas                 = var.max_replicas
  enable_ingress               = var.enable_ingress
  external_ingress             = var.external_ingress
  target_port                  = var.target_port
  environment_variables        = var.environment_variables
  tags                         = module.naming_app.tags
}

# 4. Security Groups
module "security_groups" {
  source       = "../../modules/security_groups"
  project      = var.project
  environment  = var.environment
  owner_emails = var.owners
  groups = [
    { suffix = "app-readers", description = "Container App Reader access for ${var.project}-${var.name}" },
    { suffix = "app-contributors", description = "Container App Contributor access for ${var.project}-${var.name}" },
  ]
}

# 5. RBAC Assignments
module "rbac" {
  source = "../../modules/rbac_assignments"
  assignments = [
    {
      principal_id         = module.security_groups.group_ids["app-readers"]
      role_definition_name = "Reader"
      scope                = module.container_app.id
    },
    {
      principal_id         = module.security_groups.group_ids["app-contributors"]
      role_definition_name = "Contributor"
      scope                = module.container_app.id
    },
  ]
}

# 6. Diagnostic Settings (optional)
module "diagnostics" {
  source = "../../modules/diagnostic_settings"
  count  = var.enable_diagnostics ? 1 : 0

  name                       = module.naming_app.name
  target_resource_id         = module.container_app.id
  log_analytics_workspace_id = var.log_analytics_workspace_id
  logs                       = ["ContainerAppConsoleLogs", "ContainerAppSystemLogs"]
  metrics                    = ["AllMetrics"]
}
