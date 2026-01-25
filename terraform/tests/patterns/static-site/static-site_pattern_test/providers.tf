# Provider configuration for standalone testing
# When run via terraform test, providers are injected from the test file

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false  # Don't wait for purge - cleanup script handles it
      recover_soft_deleted_key_vaults = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azuread" {}
