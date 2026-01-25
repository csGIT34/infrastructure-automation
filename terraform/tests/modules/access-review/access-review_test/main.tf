# Test fixture: Access review for security groups
#
# Creates a security group and triggers an access review for it.
# Validates two-stage review configuration.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
}

variable "resource_suffix" {
  type = string
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "owner_email" {
  description = "Email address for group owner (optional)"
  type        = string
  default     = ""
}

# Get current client for group owner
data "azuread_client_config" "current" {}

# Create a test security group for the access review
resource "azuread_group" "test" {
  display_name     = "sg-tftest-access-review-${var.resource_suffix}"
  description      = "Test security group for access review Terraform testing"
  security_enabled = true
  owners           = [data.azuread_client_config.current.object_id]

  lifecycle {
    ignore_changes = [members]
  }
}

# Calculate start date as first day of next month
locals {
  # Use a fixed date format for the start_date
  # Access reviews need a future start date
  start_date = formatdate("YYYY-MM-DD", timeadd(timestamp(), "720h")) # 30 days from now
}

# Test the access-review module
module "access_review" {
  source = "../../../../modules/access-review"

  group_id   = azuread_group.test.object_id
  group_name = azuread_group.test.display_name
  start_date = local.start_date

  # Use defaults for other settings
  frequency            = "annual"
  auto_apply_decisions = true
  default_decision     = "Deny"
  stage_duration_days  = 14
}

# Outputs for assertions
output "group_id" {
  value = azuread_group.test.object_id
}

output "group_name" {
  value = azuread_group.test.display_name
}

output "review_id" {
  value = module.access_review.review_id
}

output "review_name" {
  value = module.access_review.review_name
}

output "review_enabled" {
  value = module.access_review.enabled
}

output "review_frequency" {
  value = module.access_review.frequency
}

output "review_stages" {
  value = module.access_review.stages
}
