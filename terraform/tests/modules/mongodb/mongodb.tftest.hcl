# End-to-end tests for the mongodb module
#
# Creates a Cosmos DB account with MongoDB API and validates everything.
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
run "mongodb_cosmos_db" {
  command = apply

  module {
    source = "./mongodb_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Cosmos DB Account Creation ===
  assert {
    condition     = output.account_id != ""
    error_message = "Cosmos DB account ID should not be empty"
  }

  assert {
    condition     = output.endpoint != ""
    error_message = "Cosmos DB endpoint should not be empty"
  }

  assert {
    condition     = can(regex("^https://.*\\.documents\\.azure\\.com", output.endpoint))
    error_message = "Cosmos DB endpoint should be valid Azure URL"
  }

  # === Database Creation ===
  assert {
    condition     = output.database_name != ""
    error_message = "MongoDB database name should not be empty"
  }

  assert {
    condition     = can(regex("-db$", output.database_name))
    error_message = "MongoDB database name should end with -db suffix"
  }

  # === Connection String ===
  assert {
    condition     = output.connection_string != ""
    error_message = "Connection string should not be empty"
  }

  # === Resource Group ===
  assert {
    condition     = can(regex("^rg-tftest-mongodb-", output.resource_group_name))
    error_message = "Resource group should follow naming convention"
  }
}
