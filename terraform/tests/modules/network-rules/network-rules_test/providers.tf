# Provider configuration for standalone testing
# When run via terraform test, providers are injected from the test file

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
