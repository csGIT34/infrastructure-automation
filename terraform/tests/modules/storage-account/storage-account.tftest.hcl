# End-to-end tests for the storage-account module
#
# Creates a Storage Account with containers and validates.
# Authentication: Uses ARM_* environment variables

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

run "storage_with_containers" {
  command = apply

  module {
    source = "./storage_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Storage Account Creation ===
  assert {
    condition     = output.storage_name != ""
    error_message = "Storage account name should not be empty"
  }

  assert {
    condition     = output.storage_id != ""
    error_message = "Storage account ID should not be empty"
  }

  assert {
    condition     = can(regex("^https://.*\\.blob\\.core\\.windows\\.net/$", output.primary_blob_endpoint))
    error_message = "Primary blob endpoint should be valid Azure blob URL"
  }

  # Storage account naming rules
  assert {
    condition     = output.storage_name == lower(output.storage_name)
    error_message = "Storage account name should be lowercase"
  }

  assert {
    condition     = !can(regex("-", output.storage_name))
    error_message = "Storage account name should not contain hyphens"
  }

  # === Containers ===
  assert {
    condition     = length(output.containers) == 3
    error_message = "Should have created 3 containers"
  }

  assert {
    condition     = contains(output.containers, "data")
    error_message = "Should have 'data' container"
  }

  assert {
    condition     = contains(output.containers, "logs")
    error_message = "Should have 'logs' container"
  }
}
