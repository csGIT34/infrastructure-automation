# End-to-end tests for the function-app PATTERN
#
# Tests the full pattern composition (Function App + Key Vault + Security Groups + RBAC + Access Reviews).
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

run "deploy_function_app_pattern" {
  command = apply

  module {
    source = "./function-app_pattern_test"
  }

  variables {
    resource_suffix = run.setup.suffix
    owner_email     = var.test_owner_email
  }

  # === Function App ===
  assert {
    condition     = output.function_app.name != ""
    error_message = "Function App name should not be empty"
  }

  assert {
    condition     = output.function_app.url != ""
    error_message = "Function App URL should not be empty"
  }

  assert {
    condition     = can(regex("^https://.*\\.azurewebsites\\.net$", output.function_app.url))
    error_message = "Function App URL should be valid Azure URL"
  }

  assert {
    condition     = output.function_app.principal_id != ""
    error_message = "Function App should have a managed identity"
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
    condition     = contains(keys(output.security_groups), "func-developers")
    error_message = "Should have 'func-developers' security group"
  }

  assert {
    condition     = contains(keys(output.security_groups), "func-admins")
    error_message = "Should have 'func-admins' security group"
  }

  assert {
    condition     = can(regex("^sg-tftest-", output.security_groups["func-developers"]))
    error_message = "Security group should follow naming convention"
  }

  # === Access Reviews ===
  assert {
    condition     = output.access_reviews.developers != ""
    error_message = "Access review for developers should be created"
  }

  assert {
    condition     = output.access_reviews.admins != ""
    error_message = "Access review for admins should be created"
  }

  # === Access Info ===
  assert {
    condition     = can(regex("Function App:", output.access_info))
    error_message = "Access info should include Function App details"
  }

  assert {
    condition     = can(regex("Key Vault:", output.access_info))
    error_message = "Access info should include Key Vault details"
  }

  assert {
    condition     = can(regex("func azure functionapp publish", output.access_info))
    error_message = "Access info should include deployment instructions"
  }
}
