# End-to-end tests for the static-site PATTERN
#
# Tests the full pattern composition (Static Web App + Security Groups + RBAC + Access Reviews).
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

run "deploy_static_site_pattern" {
  command = apply

  module {
    source = "./static-site_pattern_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Static Web App ===
  assert {
    condition     = output.static_web_app.name != ""
    error_message = "Static Web App name should not be empty"
  }

  assert {
    condition     = output.static_web_app.default_url != ""
    error_message = "Static Web App default URL should not be empty"
  }

  assert {
    condition     = can(regex(".*\\.azurestaticapps\\.net$", output.static_web_app.default_url))
    error_message = "Static Web App URL should be valid Azure Static Apps URL"
  }

  assert {
    condition     = output.static_web_app.id != ""
    error_message = "Static Web App ID should not be empty"
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
    condition     = contains(keys(output.security_groups), "swa-developers")
    error_message = "Should have 'swa-developers' security group"
  }

  assert {
    condition     = contains(keys(output.security_groups), "swa-admins")
    error_message = "Should have 'swa-admins' security group"
  }

  assert {
    condition     = can(regex("^sg-tftest-", output.security_groups["swa-developers"]))
    error_message = "Security group should follow naming convention"
  }

  # === Access Reviews ===
  assert {
    condition     = output.access_reviews.developers != ""
    error_message = "Developer access review should be created"
  }

  assert {
    condition     = output.access_reviews.admins != ""
    error_message = "Admin access review should be created"
  }

  # === Access Info ===
  assert {
    condition     = can(regex("Static Web App:", output.access_info))
    error_message = "Access info should include Static Web App details"
  }

  assert {
    condition     = can(regex("Security Groups:", output.access_info))
    error_message = "Access info should include Security Groups details"
  }

  assert {
    condition     = can(regex("Access Reviews:", output.access_info))
    error_message = "Access info should include Access Reviews details"
  }
}
