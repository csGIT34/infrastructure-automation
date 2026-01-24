# End-to-end tests for the web-app PATTERN
#
# Tests the full composite pattern composition:
# Static Web App + Function App + PostgreSQL + Key Vault + Security Groups + RBAC + Access Reviews
#
# Authentication: Uses ARM_* environment variables

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
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

run "deploy_web_app_pattern" {
  command = apply

  module {
    source = "./web-app_pattern_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Frontend (Static Web App) ===
  assert {
    condition     = output.frontend.name != ""
    error_message = "Static Web App name should not be empty"
  }

  assert {
    condition     = can(regex("^https://.*\\.azurestaticapps\\.net$", output.frontend.url))
    error_message = "Static Web App URL should be valid Azure Static Web App URL"
  }

  # === API (Function App) ===
  assert {
    condition     = output.api.name != ""
    error_message = "Function App name should not be empty"
  }

  assert {
    condition     = can(regex("^https://.*\\.azurewebsites\\.net$", output.api.url))
    error_message = "Function App URL should be valid Azure URL"
  }

  # === Database (PostgreSQL) ===
  assert {
    condition     = output.database.type == "postgresql"
    error_message = "Database type should be postgresql"
  }

  assert {
    condition     = output.database.server != ""
    error_message = "Database server FQDN should not be empty"
  }

  assert {
    condition     = can(regex("\\.postgres\\.database\\.azure\\.com$", output.database.server))
    error_message = "Database server should be Azure PostgreSQL"
  }

  assert {
    condition     = output.database.name != ""
    error_message = "Database name should not be empty"
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
    condition     = contains(keys(output.security_groups), "webapp-developers")
    error_message = "Should have 'webapp-developers' security group"
  }

  assert {
    condition     = contains(keys(output.security_groups), "webapp-admins")
    error_message = "Should have 'webapp-admins' security group"
  }

  assert {
    condition     = can(regex("^sg-tftest-", output.security_groups["webapp-developers"]))
    error_message = "Security group should follow naming convention"
  }

  # === Access Reviews ===
  assert {
    condition     = output.access_reviews.developers != ""
    error_message = "Developers access review should be created"
  }

  assert {
    condition     = output.access_reviews.admins != ""
    error_message = "Admins access review should be created"
  }

  # === Access Info ===
  assert {
    condition     = can(regex("Web App:", output.access_info))
    error_message = "Access info should include Web App details"
  }

  assert {
    condition     = can(regex("Frontend:", output.access_info))
    error_message = "Access info should include Frontend details"
  }

  assert {
    condition     = can(regex("API:", output.access_info))
    error_message = "Access info should include API details"
  }

  assert {
    condition     = can(regex("Database:", output.access_info))
    error_message = "Access info should include Database details"
  }

  assert {
    condition     = can(regex("Key Vault:", output.access_info))
    error_message = "Access info should include Key Vault details"
  }
}
