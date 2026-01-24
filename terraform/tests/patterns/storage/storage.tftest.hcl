# End-to-end tests for the storage PATTERN
#
# Tests the full pattern composition (Storage Account + Security Groups + RBAC).
# Authentication: Uses ARM_* environment variables

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azuread" {}

run "setup" {
  command = apply
  module {
    source = "./setup"
  }
}

run "deploy_storage_pattern" {
  command = apply

  module {
    source = "./storage_pattern_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Storage Account ===
  assert {
    condition     = output.storage_account.name != ""
    error_message = "Storage account name should not be empty"
  }

  assert {
    condition     = output.storage_account.primary_blob_endpoint != ""
    error_message = "Storage account blob endpoint should not be empty"
  }

  assert {
    condition     = can(regex("^https://.*\\.blob\\.core\\.windows\\.net/$", output.storage_account.primary_blob_endpoint))
    error_message = "Storage account blob endpoint should be valid Azure URL"
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

  # === Containers ===
  assert {
    condition     = length(output.containers) == 2
    error_message = "Should have 2 blob containers"
  }

  assert {
    condition     = contains(output.containers, "data")
    error_message = "Should have 'data' container"
  }

  assert {
    condition     = contains(output.containers, "logs")
    error_message = "Should have 'logs' container"
  }

  # === Security Groups ===
  assert {
    condition     = contains(keys(output.security_groups), "storage-readers")
    error_message = "Should have 'storage-readers' security group"
  }

  assert {
    condition     = contains(keys(output.security_groups), "storage-contributors")
    error_message = "Should have 'storage-contributors' security group"
  }

  assert {
    condition     = can(regex("^sg-tftest-", output.security_groups["storage-readers"]))
    error_message = "Security group should follow naming convention"
  }

  # === Access Reviews ===
  assert {
    condition     = output.access_reviews.readers != ""
    error_message = "Should have access review for readers group"
  }

  assert {
    condition     = output.access_reviews.contributors != ""
    error_message = "Should have access review for contributors group"
  }

  # === Access Info ===
  assert {
    condition     = can(regex("Storage Account:", output.access_info))
    error_message = "Access info should include Storage Account details"
  }

  assert {
    condition     = can(regex("Blob Endpoint:", output.access_info))
    error_message = "Access info should include Blob Endpoint"
  }
}
