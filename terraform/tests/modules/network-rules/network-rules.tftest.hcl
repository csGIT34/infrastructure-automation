# End-to-end tests for the network-rules module
#
# Creates a storage account and applies network rules to validate functionality.
# Authentication: Uses ARM_* environment variables (source setup/.env)

provider "azurerm" {
  features {
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
run "network_rules_storage" {
  command = apply

  module {
    source = "./network-rules_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Network Rules Configuration ===
  assert {
    condition     = output.configured == true
    error_message = "Network rules should be configured"
  }

  assert {
    condition     = output.default_action == "Deny"
    error_message = "Default action should be Deny"
  }

  assert {
    condition     = output.allowed_ips_count == 2
    error_message = "Should have 2 allowed IPs configured"
  }

  assert {
    condition     = output.allowed_subnets_count == 0
    error_message = "Should have 0 allowed subnets (none configured)"
  }

  # === Storage Account ===
  assert {
    condition     = output.storage_account_name != ""
    error_message = "Storage account name should not be empty"
  }

  assert {
    condition     = can(regex("^sttftest", output.storage_account_name))
    error_message = "Storage account should follow naming convention"
  }

  assert {
    condition     = output.storage_account_id != ""
    error_message = "Storage account ID should not be empty"
  }

  # === Resource Group ===
  assert {
    condition     = can(regex("^rg-tftest-netrules-", output.resource_group_name))
    error_message = "Resource group should follow naming convention"
  }
}
