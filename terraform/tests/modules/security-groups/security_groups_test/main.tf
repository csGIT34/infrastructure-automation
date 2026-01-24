# Test fixture: Security groups creation

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

# Get current user for owner
data "azuread_client_config" "current" {}

module "security_groups" {
  source = "../../../../modules/security-groups"

  project     = "tftest-${var.resource_suffix}"
  environment = "dev"

  groups = [
    {
      suffix      = "readers"
      description = "Test readers group for Terraform testing"
    },
    {
      suffix      = "admins"
      description = "Test admins group for Terraform testing"
    }
  ]

  # Use empty list - module will use current principal as owner
  owner_emails = []
}

output "group_ids" {
  value = module.security_groups.group_ids
}

output "group_names" {
  value = module.security_groups.group_names
}

output "groups" {
  value = module.security_groups.groups
}
