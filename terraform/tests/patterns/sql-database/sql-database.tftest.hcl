# End-to-end tests for the sql-database PATTERN
#
# Tests the full pattern composition (SQL Server + Database + Key Vault + Security Groups + RBAC + Access Reviews).
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
  test_owner_email = ""  # Passed via -var-file
}

run "setup" {
  command = apply
  module {
    source = "./setup"
  }
}

run "deploy_sql_database_pattern" {
  command = apply

  module {
    source = "./sql-database_pattern_test"
  }

  variables {
    resource_suffix = run.setup.suffix
    owner_email     = var.test_owner_email
  }

  # === SQL Database ===
  assert {
    condition     = output.sql_database.server_fqdn != ""
    error_message = "SQL Server FQDN should not be empty"
  }

  assert {
    condition     = can(regex("\\.database\\.windows\\.net$", output.sql_database.server_fqdn))
    error_message = "SQL Server FQDN should be valid Azure SQL endpoint"
  }

  assert {
    condition     = output.sql_database.database_name != ""
    error_message = "Database name should not be empty"
  }

  assert {
    condition     = output.sql_database.server_id != ""
    error_message = "SQL Server ID should not be empty"
  }

  assert {
    condition     = output.sql_database.database_id != ""
    error_message = "SQL Database ID should not be empty"
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
    condition     = contains(keys(output.security_groups), "sql-readers")
    error_message = "Should have 'sql-readers' security group"
  }

  assert {
    condition     = contains(keys(output.security_groups), "sql-admins")
    error_message = "Should have 'sql-admins' security group"
  }

  assert {
    condition     = can(regex("^sg-tftest-", output.security_groups["sql-readers"]))
    error_message = "Security group should follow naming convention"
  }

  assert {
    condition     = can(regex("^sg-tftest-", output.security_groups["sql-admins"]))
    error_message = "Security group should follow naming convention"
  }

  # === Access Reviews ===
  assert {
    condition     = output.access_reviews.readers != ""
    error_message = "Readers access review should be created"
  }

  assert {
    condition     = output.access_reviews.admins != ""
    error_message = "Admins access review should be created"
  }

  # === Access Info ===
  assert {
    condition     = can(regex("SQL Server:", output.access_info))
    error_message = "Access info should include SQL Server details"
  }

  assert {
    condition     = can(regex("Connection secrets stored in:", output.access_info))
    error_message = "Access info should include Key Vault reference"
  }
}
