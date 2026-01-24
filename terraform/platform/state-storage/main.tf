# terraform/platform/state-storage/main.tf
# Bootstrap infrastructure for Terraform state storage
#
# This is the foundational infrastructure that must be created first.
# It uses LOCAL state initially, then state can be migrated to itself.
#
# Provisions:
#   - Resource Group for state storage
#   - Storage Account with tfstate container
#   - Security Groups for state admins
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

  # Initially uses local state. After creation, migrate to remote:
  # terraform init -migrate-state -backend-config=backend.tfvars
  #
  # Uncomment this block after initial creation:
  # backend "azurerm" {
  #   use_oidc = true
  # }
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
  default     = "terraform-state"
}

variable "environment" {
  description = "Environment"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "business_unit" {
  description = "Business unit for tagging"
  type        = string
  default     = "platform"
}

variable "owners" {
  description = "Email addresses of state storage owners"
  type        = list(string)
  default     = []
}

variable "replication_type" {
  description = "Storage replication type (LRS, GRS, ZRS, GZRS)"
  type        = string
  default     = "GRS"
}

# -----------------------------------------------------------------------------
# Naming
# -----------------------------------------------------------------------------

module "naming" {
  source = "../../modules/naming"

  project       = var.project
  environment   = var.environment
  resource_type = "resource_group"
  name          = "state"
  business_unit = var.business_unit
}

module "storage_naming" {
  source = "../../modules/naming"

  project       = var.project
  environment   = var.environment
  resource_type = "storage_account"
  name          = "tfstate"
  business_unit = var.business_unit
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "state" {
  name     = module.naming.resource_group_name
  location = var.location

  tags = merge(module.naming.tags, {
    Purpose = "Terraform State Storage"
  })
}

# -----------------------------------------------------------------------------
# Storage Account for Terraform State
# -----------------------------------------------------------------------------

module "storage" {
  source = "../../modules/storage-account"

  name                = module.storage_naming.name
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location

  config = {
    tier            = "Standard"
    replication     = var.replication_type
    versioning      = true
    soft_delete_days = 30

    containers = [
      {
        name        = "tfstate"
        access_type = "private"
      }
    ]
  }

  tags = merge(module.naming.tags, {
    Purpose = "Terraform State Storage"
  })
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
      suffix      = "state-readers"
      description = "Read access to Terraform state"
    },
    {
      suffix      = "state-admins"
      description = "Full access to Terraform state storage"
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
    # State readers - can read state but not modify
    {
      principal_id         = module.security_groups.group_ids["state-readers"]
      role_definition_name = "Storage Blob Data Reader"
      scope                = module.storage.id
      description          = "Terraform state readers"
    },
    # State admins - full access to state
    {
      principal_id         = module.security_groups.group_ids["state-admins"]
      role_definition_name = "Storage Blob Data Contributor"
      scope                = module.storage.id
      description          = "Terraform state admins"
    },
    {
      principal_id         = module.security_groups.group_ids["state-admins"]
      role_definition_name = "Contributor"
      scope                = azurerm_resource_group.state.id
      description          = "State admins - manage storage resources"
    }
  ]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.state.name
}

output "storage_account_name" {
  description = "Storage account name for Terraform backend"
  value       = module.storage.name
}

output "container_name" {
  description = "Container name for Terraform state"
  value       = "tfstate"
}

output "security_groups" {
  description = "Security group names"
  value       = module.security_groups.group_names
}

output "backend_config" {
  description = "Backend configuration for other Terraform configs"
  value       = <<-EOT
    # Add to backend.tfvars:
    resource_group_name  = "${azurerm_resource_group.state.name}"
    storage_account_name = "${module.storage.name}"
    container_name       = "tfstate"
    key                  = "<your-state-path>/terraform.tfstate"
  EOT
}

output "backend_config_hcl" {
  description = "Backend block for main.tf files"
  value       = <<-EOT
    # Add to terraform block:
    backend "azurerm" {
      resource_group_name  = "${azurerm_resource_group.state.name}"
      storage_account_name = "${module.storage.name}"
      container_name       = "tfstate"
      key                  = "<your-state-path>/terraform.tfstate"
      use_oidc             = true
    }
  EOT
}

output "migration_instructions" {
  description = "Instructions for migrating this config to remote state"
  value       = <<-EOT
    State Storage Created!

    Resource Group: ${azurerm_resource_group.state.name}
    Storage Account: ${module.storage.name}
    Container: tfstate

    To migrate THIS config to use remote state:
    1. Uncomment the backend "azurerm" block in main.tf
    2. Create backend.tfvars with:
       resource_group_name  = "${azurerm_resource_group.state.name}"
       storage_account_name = "${module.storage.name}"
       container_name       = "tfstate"
       key                  = "platform/state-storage/terraform.tfstate"

    3. Run: terraform init -migrate-state -backend-config=backend.tfvars

    For other Terraform configs, use:
       key = "platform/<component>/terraform.tfstate"
       key = "<business_unit>/<env>/<project>/<pattern>/terraform.tfstate"
  EOT
}
