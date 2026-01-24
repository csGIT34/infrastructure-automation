# End-to-end tests for the azure-sql module
#
# Creates an Azure SQL Server with database and validates everything.
# Authentication: Uses ARM_* environment variables (source setup/.env)

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false  # Handled by cleanup script
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
run "azure_sql_with_database" {
  command = apply

  module {
    source = "./azure-sql_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === SQL Server Creation ===
  assert {
    condition     = output.server_id != ""
    error_message = "SQL Server ID should not be empty"
  }

  assert {
    condition     = output.server_name != ""
    error_message = "SQL Server name should not be empty"
  }

  assert {
    condition     = can(regex("^sql-tftest-", output.server_name))
    error_message = "SQL Server name should follow naming convention"
  }

  # === Server FQDN ===
  assert {
    condition     = output.server_fqdn != ""
    error_message = "SQL Server FQDN should not be empty"
  }

  assert {
    condition     = can(regex("\\.database\\.windows\\.net$", output.server_fqdn))
    error_message = "SQL Server FQDN should be valid Azure SQL endpoint"
  }

  # === Database Creation ===
  assert {
    condition     = length(output.databases) == 1
    error_message = "Should have 1 database created"
  }

  assert {
    condition     = contains(keys(output.databases), "testdb")
    error_message = "Should have testdb database"
  }

  assert {
    condition     = output.database_name == "testdb"
    error_message = "Database name should be testdb"
  }

  # === Admin Login ===
  assert {
    condition     = output.admin_login != ""
    error_message = "Admin login should not be empty"
  }

  # === Connection String Template ===
  assert {
    condition     = output.connection_string_template != ""
    error_message = "Connection string template should not be empty"
  }

  assert {
    condition     = can(regex("Server=tcp:", output.connection_string_template))
    error_message = "Connection string should contain Server=tcp:"
  }

  # === Resource Group ===
  assert {
    condition     = can(regex("^rg-tftest-azure-sql-", output.resource_group_name))
    error_message = "Resource group should follow naming convention"
  }
}
