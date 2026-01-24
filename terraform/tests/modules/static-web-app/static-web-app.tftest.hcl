# End-to-end tests for the static-web-app module
#
# Creates a Static Web App and validates outputs.
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
run "static_web_app_creation" {
  command = apply

  module {
    source = "./static-web-app_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Static Web App Creation ===
  assert {
    condition     = output.static_web_app_name != ""
    error_message = "Static Web App name should not be empty"
  }

  assert {
    condition     = output.static_web_app_id != ""
    error_message = "Static Web App ID should not be empty"
  }

  assert {
    condition     = can(regex("^stapp-tftest-", output.static_web_app_name))
    error_message = "Static Web App name should follow naming convention"
  }

  # === Host Name ===
  assert {
    condition     = output.default_host_name != ""
    error_message = "Default host name should not be empty"
  }

  assert {
    condition     = can(regex("\\.azurestaticapps\\.net$", output.default_host_name))
    error_message = "Default host name should be an Azure Static Apps URL"
  }

  # === Resource Group ===
  assert {
    condition     = can(regex("^rg-tftest-staticwebapp-", output.resource_group_name))
    error_message = "Resource group should follow naming convention"
  }
}
