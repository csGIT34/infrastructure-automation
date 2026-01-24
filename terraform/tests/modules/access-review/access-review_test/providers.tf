# Provider configuration for standalone testing
# When run via terraform test, providers are injected from the test file

provider "azuread" {}

provider "msgraph" {
  # Uses ARM_* environment variables for authentication
}
