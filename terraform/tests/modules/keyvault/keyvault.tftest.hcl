# End-to-end tests for the keyvault module
#
# Creates a single Key Vault with secrets and validates everything.
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

# Generate unique suffix
run "setup" {
  command = apply
  module {
    source = "./setup"
  }
}

# Single comprehensive test
run "keyvault_with_secrets" {
  command = apply

  module {
    source = "./keyvault_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Key Vault Creation ===
  assert {
    condition     = output.vault_name != ""
    error_message = "Key Vault name should not be empty"
  }

  assert {
    condition     = output.vault_uri != ""
    error_message = "Key Vault URI should not be empty"
  }

  assert {
    condition     = can(regex("^https://.*\\.vault\\.azure\\.net/$", output.vault_uri))
    error_message = "Key Vault URI should be valid Azure URL"
  }

  assert {
    condition     = output.vault_id != ""
    error_message = "Key Vault ID should not be empty"
  }

  # === Secrets Storage ===
  assert {
    condition     = length(output.secret_uris) == 2
    error_message = "Should have 2 secrets stored"
  }

  assert {
    condition     = contains(keys(output.secret_uris), "db-connection-string")
    error_message = "Should have db-connection-string secret"
  }

  assert {
    condition     = contains(keys(output.secret_uris), "api-key")
    error_message = "Should have api-key secret"
  }

  # === Resource Group ===
  assert {
    condition     = can(regex("^rg-tftest-keyvault-", output.resource_group_name))
    error_message = "Resource group should follow naming convention"
  }
}
