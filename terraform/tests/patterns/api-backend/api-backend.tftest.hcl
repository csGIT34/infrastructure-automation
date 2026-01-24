# End-to-end tests for the api-backend pattern
#
# Tests Function App + Key Vault + Security Groups + Access Reviews
# Authentication: Uses ARM_* environment variables (source setup/.env)

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false  # Handled by cleanup script
      recover_soft_deleted_key_vaults = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azuread" {}

provider "msgraph" {}

# Generate unique suffix
run "setup" {
  command = apply
  module {
    source = "./setup"
  }
}

# Deploy API Backend pattern
run "deploy_api_backend_pattern" {
  command = apply

  module {
    source = "./api-backend_pattern_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Function App ===
  assert {
    condition     = output.api.name != ""
    error_message = "Function App name should not be empty"
  }

  assert {
    condition     = output.api.url != ""
    error_message = "Function App URL should not be empty"
  }

  assert {
    condition     = output.api.principal_id != ""
    error_message = "Function App should have managed identity"
  }

  # === Key Vault ===
  assert {
    condition     = output.keyvault.name != ""
    error_message = "Key Vault name should not be empty"
  }

  assert {
    condition     = output.keyvault.uri != ""
    error_message = "Key Vault URI should not be empty"
  }

  assert {
    condition     = can(regex("^https://.*\\.vault\\.azure\\.net/$", output.keyvault.uri))
    error_message = "Key Vault URI should be valid Azure URL"
  }

  # === Security Groups ===
  assert {
    condition     = contains(keys(output.security_groups), "api-developers")
    error_message = "Should have api-developers security group"
  }

  assert {
    condition     = contains(keys(output.security_groups), "api-admins")
    error_message = "Should have api-admins security group"
  }

  # === Access Reviews ===
  assert {
    condition     = output.access_reviews.developers != ""
    error_message = "Developers access review should be created"
  }

  assert {
    condition     = output.access_reviews.admins != ""
    error_message = "Admins access review should be created"
  }

  # === Resource Group ===
  assert {
    condition     = can(regex("^rg-tftest-.*-api-backend-dev$", output.resource_group))
    error_message = "Resource group should follow naming convention"
  }
}
