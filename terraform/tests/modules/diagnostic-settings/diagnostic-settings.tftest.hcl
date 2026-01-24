# End-to-end tests for the diagnostic-settings module
#
# Creates a Key Vault with diagnostic settings configured to send logs
# to a Log Analytics workspace, then validates the configuration.
# Authentication: Uses ARM_* environment variables (source setup/.env)

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false # Handled by cleanup script
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
run "diagnostic_settings_with_log_analytics" {
  command = apply

  module {
    source = "./diagnostic-settings_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Diagnostic Setting Creation ===
  assert {
    condition     = output.diagnostic_setting_id != ""
    error_message = "Diagnostic setting ID should not be empty"
  }

  assert {
    condition     = output.diagnostic_setting_name != ""
    error_message = "Diagnostic setting name should not be empty"
  }

  assert {
    condition     = can(regex("^diag-tftest-", output.diagnostic_setting_name))
    error_message = "Diagnostic setting name should follow naming convention (diag-tftest-*)"
  }

  # === Target Resource Validation ===
  assert {
    condition     = output.target_resource_id != ""
    error_message = "Target resource ID should not be empty"
  }

  assert {
    condition     = can(regex("/Microsoft.KeyVault/vaults/", output.target_resource_id))
    error_message = "Target resource should be a Key Vault"
  }

  # === Log Analytics Workspace Validation ===
  assert {
    condition     = output.log_analytics_workspace_id != ""
    error_message = "Log Analytics workspace ID should not be empty"
  }

  assert {
    condition     = can(regex("/Microsoft.OperationalInsights/workspaces/", output.log_analytics_workspace_id))
    error_message = "Log Analytics workspace ID should be valid"
  }

  # === Resource Group ===
  assert {
    condition     = can(regex("^rg-tftest-diag-", output.resource_group_name))
    error_message = "Resource group should follow naming convention"
  }
}
