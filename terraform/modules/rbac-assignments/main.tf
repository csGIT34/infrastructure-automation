# terraform/modules/rbac-assignments/main.tf
# Assigns Azure RBAC roles to security groups or identities

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

variable "assignments" {
  description = "List of role assignments to create"
  type = list(object({
    principal_id         = string
    role_definition_name = string
    scope                = string
    description          = optional(string, "")
  }))
}

variable "skip_service_principal_check" {
  description = "Skip AAD check for service principals (useful for managed identities)"
  type        = bool
  default     = false
}

resource "azurerm_role_assignment" "assignments" {
  for_each = { for idx, a in var.assignments : idx => a }

  principal_id                     = each.value.principal_id
  role_definition_name             = each.value.role_definition_name
  scope                            = each.value.scope
  description                      = each.value.description != "" ? each.value.description : null
  skip_service_principal_aad_check = var.skip_service_principal_check
}

output "assignment_ids" {
  description = "List of role assignment IDs"
  value       = [for a in azurerm_role_assignment.assignments : a.id]
}

output "assignments" {
  description = "Map of assignment details"
  value = { for idx, a in azurerm_role_assignment.assignments : idx => {
    id                   = a.id
    principal_id         = a.principal_id
    role_definition_name = a.role_definition_name
    scope                = a.scope
  } }
}
