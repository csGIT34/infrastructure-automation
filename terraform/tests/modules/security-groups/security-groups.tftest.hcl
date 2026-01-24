# End-to-end tests for the security-groups module
#
# Creates Entra ID security groups and validates.
# Authentication: Uses ARM_* environment variables

provider "azuread" {}

run "setup" {
  command = apply
  module {
    source = "./setup"
  }
}

run "create_security_groups" {
  command = apply

  module {
    source = "./security_groups_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Groups Created ===
  assert {
    condition     = length(output.group_ids) == 2
    error_message = "Should have created 2 security groups"
  }

  assert {
    condition     = contains(keys(output.group_ids), "readers")
    error_message = "Should have 'readers' group"
  }

  assert {
    condition     = contains(keys(output.group_ids), "admins")
    error_message = "Should have 'admins' group"
  }

  # === Naming Convention ===
  assert {
    condition     = can(regex("^sg-tftest-", output.group_names["readers"]))
    error_message = "Group name should follow sg-{project}-{env}-{suffix} convention"
  }

  # === Valid GUIDs ===
  assert {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", output.group_ids["readers"]))
    error_message = "Group ID should be a valid GUID"
  }

  assert {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", output.group_ids["admins"]))
    error_message = "Admin group ID should be a valid GUID"
  }
}
