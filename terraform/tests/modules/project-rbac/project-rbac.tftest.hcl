# End-to-end tests for the project-rbac module
#
# Creates Entra ID security groups and Azure RBAC assignments.
# Authentication: Uses ARM_* environment variables (source setup/.env)

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azuread" {}

# Generate unique suffix
run "setup" {
  command = apply
  module {
    source = "./setup"
  }
}

# Single comprehensive test
run "project_rbac_with_groups" {
  command = apply

  module {
    source = "./project-rbac_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Groups Created ===
  assert {
    condition     = length(output.group_ids) >= 2
    error_message = "Should have created at least 2 security groups (readers, secrets)"
  }

  assert {
    condition     = contains(output.groups_created, "readers")
    error_message = "Should have 'readers' group created"
  }

  assert {
    condition     = contains(output.groups_created, "secrets")
    error_message = "Should have 'secrets' group created (keyvault_id was provided)"
  }

  # === Group IDs are valid GUIDs ===
  assert {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", output.group_ids["readers"]))
    error_message = "Readers group ID should be a valid GUID"
  }

  assert {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", output.group_ids["secrets"]))
    error_message = "Secrets group ID should be a valid GUID"
  }

  # === Naming Convention ===
  assert {
    condition     = can(regex("^sg-tftest-.*-dev-readers$", output.group_names["readers"]))
    error_message = "Readers group name should follow sg-{project}-{env}-readers convention"
  }

  assert {
    condition     = can(regex("^sg-tftest-.*-dev-secrets$", output.group_names["secrets"]))
    error_message = "Secrets group name should follow sg-{project}-{env}-secrets convention"
  }

  # === Resource Group ===
  assert {
    condition     = can(regex("^rg-tftest-project-rbac-", output.resource_group_name))
    error_message = "Resource group should follow naming convention"
  }

  # === Key Vault Created ===
  assert {
    condition     = can(regex("^kv-tftest-rbac-", output.keyvault_name))
    error_message = "Key Vault should follow naming convention"
  }
}
