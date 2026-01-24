# Shared provider configuration for tests
#
# This file is referenced by test files via the provider block.
# Authentication uses Azure CLI credentials locally, OIDC in CI.

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

# Provider configuration for tests
# Uses Azure CLI auth locally, OIDC in GitHub Actions
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = var.test_subscription_id
}

provider "azuread" {
  tenant_id = var.test_tenant_id
}
