# End-to-end tests for the function-app module
#
# Creates an Azure Function App and validates.
# Authentication: Uses ARM_* environment variables
#
# Note: Function App provisioning takes 3-5 minutes.

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

run "setup" {
  command = apply
  module {
    source = "./setup"
  }
}

run "create_function_app" {
  command = apply

  module {
    source = "./function_app_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Function App Created ===
  assert {
    condition     = output.function_name != ""
    error_message = "Function app name should not be empty"
  }

  assert {
    condition     = output.function_id != ""
    error_message = "Function app ID should not be empty"
  }

  assert {
    condition     = can(regex("^https://.*\\.azurewebsites\\.net$", output.function_url))
    error_message = "Function app URL should be valid Azure Functions URL"
  }

  # === Managed Identity ===
  assert {
    condition     = output.principal_id != ""
    error_message = "Managed identity principal ID should not be empty"
  }

  assert {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", output.principal_id))
    error_message = "Principal ID should be a valid GUID"
  }

  # === Storage Account ===
  assert {
    condition     = output.storage_account_name != ""
    error_message = "Storage account name should not be empty"
  }
}
