# End-to-end tests for the mongodb PATTERN
#
# Tests the full pattern composition (MongoDB/CosmosDB + Key Vault + Security Groups + RBAC).
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

run "setup" {
  command = apply
  module {
    source = "./setup"
  }
}

run "deploy_mongodb_pattern" {
  command = apply

  module {
    source = "./mongodb_pattern_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === MongoDB (Cosmos DB) ===
  assert {
    condition     = output.mongodb.endpoint != ""
    error_message = "MongoDB endpoint should not be empty"
  }

  assert {
    condition     = can(regex("^https://.*\\.documents\\.azure\\.com", output.mongodb.endpoint))
    error_message = "MongoDB endpoint should be valid Cosmos DB URL"
  }

  assert {
    condition     = output.mongodb.account_id != ""
    error_message = "MongoDB account ID should not be empty"
  }

  assert {
    condition     = output.mongodb.database_name != ""
    error_message = "MongoDB database name should not be empty"
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
    condition     = contains(keys(output.security_groups), "mongo-readers")
    error_message = "Should have 'mongo-readers' security group"
  }

  assert {
    condition     = contains(keys(output.security_groups), "mongo-admins")
    error_message = "Should have 'mongo-admins' security group"
  }

  assert {
    condition     = can(regex("^sg-tftest-", output.security_groups["mongo-readers"]))
    error_message = "Security group should follow naming convention"
  }

  # === Access Reviews ===
  assert {
    condition     = output.access_reviews.readers != ""
    error_message = "Access review for readers should be created"
  }

  assert {
    condition     = output.access_reviews.admins != ""
    error_message = "Access review for admins should be created"
  }

  # === Access Info ===
  assert {
    condition     = can(regex("MongoDB:", output.access_info))
    error_message = "Access info should include MongoDB details"
  }

  assert {
    condition     = can(regex("Key Vault:", output.access_info))
    error_message = "Access info should include Key Vault details"
  }
}
