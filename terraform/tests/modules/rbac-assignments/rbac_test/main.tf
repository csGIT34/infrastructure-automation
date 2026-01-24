# Test fixture: RBAC role assignments

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
  }
}

variable "resource_group_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

module "rbac" {
  source = "../../../../modules/rbac-assignments"

  assignments = [
    {
      principal_id         = var.security_group_id
      role_definition_name = "Reader"
      scope                = var.resource_group_id
      description          = "Test Reader assignment"
    },
    {
      principal_id         = var.security_group_id
      role_definition_name = "Contributor"
      scope                = var.resource_group_id
      description          = "Test Contributor assignment"
    }
  ]
}

output "assignment_ids" {
  value = module.rbac.assignment_ids
}

output "assignments" {
  value = module.rbac.assignments
}
