# End-to-end tests for the postgresql PATTERN
#
# Tests the full pattern composition (PostgreSQL + Key Vault + Security Groups + RBAC + Access Reviews).
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
  test_owner_email = ""        # Passed via -var-file
  test_location    = "westus2" # PostgreSQL restricted in eastus/eastus2
}

run "setup" {
  command = apply
  module {
    source = "./setup"
  }
}

run "deploy_postgresql_pattern" {
  command = apply

  module {
    source = "./postgresql_pattern_test"
  }

  variables {
    resource_suffix = run.setup.suffix
    owner_email     = var.test_owner_email
    location        = var.test_location
  }

  # === PostgreSQL ===
  assert {
    condition     = output.postgresql.server_fqdn != ""
    error_message = "PostgreSQL server FQDN should not be empty"
  }

  assert {
    condition     = can(regex("\\.postgres\\.database\\.azure\\.com$", output.postgresql.server_fqdn))
    error_message = "PostgreSQL server FQDN should be valid Azure PostgreSQL URL"
  }

  assert {
    condition     = output.postgresql.database_name != ""
    error_message = "PostgreSQL database name should not be empty"
  }

  assert {
    condition     = output.postgresql.server_id != ""
    error_message = "PostgreSQL server ID should not be empty"
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
    condition     = contains(keys(output.security_groups), "db-readers")
    error_message = "Should have 'db-readers' security group"
  }

  assert {
    condition     = contains(keys(output.security_groups), "db-admins")
    error_message = "Should have 'db-admins' security group"
  }

  assert {
    condition     = can(regex("^sg-tftest-", output.security_groups["db-readers"]))
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
    condition     = can(regex("PostgreSQL Server:", output.access_info))
    error_message = "Access info should include PostgreSQL server details"
  }

  assert {
    condition     = can(regex("Connection secrets stored in:", output.access_info))
    error_message = "Access info should include Key Vault details"
  }

  assert {
    condition     = can(regex("Access Reviews:", output.access_info))
    error_message = "Access info should include access review details"
  }
}
