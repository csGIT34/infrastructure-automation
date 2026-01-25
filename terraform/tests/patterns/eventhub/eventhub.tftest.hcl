# End-to-end tests for the eventhub PATTERN
#
# Tests the full pattern composition (Event Hub + Key Vault + Security Groups + RBAC + Access Reviews).
# Authentication: Uses ARM_* environment variables

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
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

run "deploy_eventhub_pattern" {
  command = apply

  module {
    source = "./eventhub_pattern_test"
  }

  variables {
    resource_suffix = run.setup.suffix
    owner_email     = var.test_owner_email
  }

  # === Event Hub ===
  assert {
    condition     = output.eventhub.namespace_name != ""
    error_message = "Event Hub namespace name should not be empty"
  }

  assert {
    condition     = output.eventhub.namespace_id != ""
    error_message = "Event Hub namespace ID should not be empty"
  }

  assert {
    condition     = length(output.eventhub.hubs) > 0
    error_message = "Event Hub should have at least one hub"
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
    condition     = contains(keys(output.security_groups), "eventhub-senders")
    error_message = "Should have 'eventhub-senders' security group"
  }

  assert {
    condition     = contains(keys(output.security_groups), "eventhub-receivers")
    error_message = "Should have 'eventhub-receivers' security group"
  }

  assert {
    condition     = can(regex("^sg-tftest-", output.security_groups["eventhub-senders"]))
    error_message = "Security group should follow naming convention"
  }

  # === Access Reviews ===
  assert {
    condition     = output.access_reviews.senders != ""
    error_message = "Senders access review should be created"
  }

  assert {
    condition     = output.access_reviews.receivers != ""
    error_message = "Receivers access review should be created"
  }

  # === Access Info ===
  assert {
    condition     = can(regex("Event Hub Namespace:", output.access_info))
    error_message = "Access info should include Event Hub details"
  }

  assert {
    condition     = can(regex("Key Vault:", output.access_info))
    error_message = "Access info should include Key Vault details"
  }
}
