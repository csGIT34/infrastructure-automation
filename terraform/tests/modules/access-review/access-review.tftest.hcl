# End-to-end tests for the access-review module
#
# Creates a security group and triggers access review creation via Graph API.
# Note: Access reviews are created but NOT tracked in Terraform state
# to avoid 404 errors when reviews are modified externally in Entra ID.
# Authentication: Uses ARM_* environment variables (source setup/.env)

provider "azuread" {}

# Generate unique suffix
run "setup" {
  command = apply
  module {
    source = "./setup"
  }
}

# Test access review creation
run "access_review_creation" {
  command = apply

  module {
    source = "./access-review_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Security Group Created ===
  assert {
    condition     = output.group_id != ""
    error_message = "Security group ID should not be empty"
  }

  assert {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", output.group_id))
    error_message = "Security group ID should be a valid GUID"
  }

  assert {
    condition     = can(regex("^sg-tftest-access-review-", output.group_name))
    error_message = "Security group name should follow naming convention"
  }

  # === Access Review Triggered ===
  # Note: review_id is the null_resource trigger ID, not the Graph API ID
  # The actual access review is created via Azure CLI and not tracked in state
  assert {
    condition     = output.review_id != ""
    error_message = "Access review trigger ID should not be empty"
  }

  assert {
    condition     = output.review_enabled == true
    error_message = "Access review should be enabled"
  }

  # === Review Configuration ===
  assert {
    condition     = output.review_frequency == "annual"
    error_message = "Access review frequency should be 'annual'"
  }

  assert {
    condition     = can(regex("^Access Review: sg-tftest-access-review-", output.review_name))
    error_message = "Access review name should follow expected format"
  }

  # === Two-Stage Review ===
  assert {
    condition     = length(output.review_stages) == 2
    error_message = "Access review should have 2 stages"
  }

  assert {
    condition     = contains(output.review_stages, "Group Owners")
    error_message = "Stage 1 should be 'Group Owners'"
  }

  assert {
    condition     = contains(output.review_stages, "Member's Manager")
    error_message = "Stage 2 should be 'Member's Manager'"
  }
}
