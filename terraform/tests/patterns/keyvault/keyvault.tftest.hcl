# End-to-end tests for the keyvault PATTERN
#
# Tests the full pattern composition (KV + Security Groups + RBAC).
# Authentication: Uses ARM_* environment variables

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
}

provider "azuread" {}

# Variables from terraform.tfvars
variables {
  test_owner_email = ""  # Passed via -var-file
}

run "setup" {
  command = apply
  module {
    source = "./setup"
  }
}

run "deploy_keyvault_pattern" {
  command = apply

  module {
    source = "./keyvault_pattern_test"
  }

  variables {
    resource_suffix = run.setup.suffix
    owner_email     = var.test_owner_email
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

  # === Resource Group ===
  assert {
    condition     = output.resource_group != ""
    error_message = "Resource group should not be empty"
  }

  assert {
    condition     = can(regex("^rg-tftest-", output.resource_group))
    error_message = "Resource group should follow naming convention"
  }

  # === Security Groups ===
  assert {
    condition     = contains(keys(output.security_groups), "secrets-readers")
    error_message = "Should have 'secrets-readers' security group"
  }

  assert {
    condition     = contains(keys(output.security_groups), "secrets-admins")
    error_message = "Should have 'secrets-admins' security group"
  }

  assert {
    condition     = can(regex("^sg-tftest-", output.security_groups["secrets-readers"]))
    error_message = "Security group should follow naming convention"
  }

  # === Access Info ===
  assert {
    condition     = can(regex("Key Vault:", output.access_info))
    error_message = "Access info should include Key Vault details"
  }
}
