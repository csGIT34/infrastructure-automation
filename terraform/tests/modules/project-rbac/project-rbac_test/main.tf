# Test fixture: Project RBAC with security groups
#
# Single consolidated test that validates:
# - Security group creation (readers, secrets)
# - RBAC assignments on resource group
# - Key Vault secrets access (optional)

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
  description = "Email for group owner (optional, uses current principal if empty)"
  type        = string
  default     = ""
}

# Create test resource group
resource "azurerm_resource_group" "test" {
  name     = "rg-tftest-project-rbac-${var.resource_suffix}"
  location = var.location

  tags = {
    Purpose = "Terraform-Test"
    Module  = "project-rbac"
  }
}

# Create a test Key Vault to test secrets group functionality
resource "azurerm_key_vault" "test" {
  name                = "kv-tftest-rbac-${var.resource_suffix}"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  tenant_id           = data.azuread_client_config.current.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = true

  tags = {
    Purpose = "Terraform-Test"
    Module  = "project-rbac"
  }
}

# Get current client config for tenant ID
data "azuread_client_config" "current" {}

# Test the project-rbac module
module "project_rbac" {
  source = "../../../../modules/project-rbac"

  project_name      = "tftest-${var.resource_suffix}"
  environment       = "dev"
  resource_group_id = azurerm_resource_group.test.id
  keyvault_id       = azurerm_key_vault.test.id

  # Use empty list - module will use current principal as owner
  # Or use the provided owner_email if set
  owner_emails = var.owner_email != "" ? [var.owner_email] : []

  # Enable groups for testing
  enable_secrets_group   = true
  enable_deployers_group = false
  enable_data_group      = false
  enable_compute_group   = false

  tags = {
    Purpose = "Terraform-Test"
  }
}

# Outputs for assertions
output "group_ids" {
  value = module.project_rbac.group_ids
}

output "group_names" {
  value = module.project_rbac.group_names
}

output "groups_created" {
  value = module.project_rbac.groups_created
}

output "resource_group_name" {
  value = azurerm_resource_group.test.name
}

output "keyvault_name" {
  value = azurerm_key_vault.test.name
}
