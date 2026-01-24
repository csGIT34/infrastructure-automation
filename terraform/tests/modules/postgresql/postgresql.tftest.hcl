# End-to-end tests for the postgresql module
#
# Creates a PostgreSQL Flexible Server and validates.
# Authentication: Uses ARM_* environment variables
#
# Note: PostgreSQL provisioning takes 5-10 minutes.

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

run "create_postgresql" {
  command = apply

  module {
    source = "./postgresql_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Server Created ===
  assert {
    condition     = output.server_fqdn != ""
    error_message = "Server FQDN should not be empty"
  }

  assert {
    condition     = can(regex("\\.postgres\\.database\\.azure\\.com$", output.server_fqdn))
    error_message = "Server FQDN should be valid Azure PostgreSQL endpoint"
  }

  assert {
    condition     = output.server_id != ""
    error_message = "Server ID should not be empty"
  }

  # === Database Created ===
  assert {
    condition     = output.database_name != ""
    error_message = "Database name should not be empty"
  }

  assert {
    condition     = can(regex("-db$", output.database_name))
    error_message = "Database name should end with '-db'"
  }
}
