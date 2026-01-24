# End-to-end tests for the rbac-assignments module
#
# Creates Azure RBAC role assignments and validates.
# Authentication: Uses ARM_* environment variables

provider "azurerm" {
  features {
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

run "create_rbac_assignments" {
  command = apply

  module {
    source = "./rbac_test"
  }

  variables {
    resource_group_id   = run.setup.resource_group_id
    security_group_id   = run.setup.security_group_id
  }

  # === Assignments Created ===
  assert {
    condition     = length(output.assignment_ids) == 2
    error_message = "Should have created 2 role assignments"
  }

  assert {
    condition     = alltrue([for id in output.assignment_ids : id != ""])
    error_message = "All assignment IDs should be non-empty"
  }

  assert {
    condition     = length(output.assignments) == 2
    error_message = "Should have 2 assignments in details map"
  }
}
