# terraform/modules/security-groups/main.tf
# Creates Entra ID security groups with owner delegation

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "groups" {
  description = "List of security groups to create"
  type = list(object({
    suffix      = string # e.g., "readers", "admins"
    description = string
  }))
}

variable "owner_emails" {
  description = "Email addresses of group owners"
  type        = list(string)
}

# Look up owners by email
data "azuread_users" "owners" {
  count                = length(var.owner_emails) > 0 ? 1 : 0
  user_principal_names = var.owner_emails
}

# Get current client for fallback owner
data "azuread_client_config" "current" {}

locals {
  # Always include the creating principal as owner (required with Group.Create permission)
  # Plus any user-specified owners
  user_owner_ids = length(var.owner_emails) > 0 ? data.azuread_users.owners[0].object_ids : []
  owner_ids      = distinct(concat([data.azuread_client_config.current.object_id], local.user_owner_ids))
}

resource "azuread_group" "groups" {
  for_each = { for g in var.groups : g.suffix => g }

  display_name     = "sg-${var.project}-${var.environment}-${each.key}"
  description      = each.value.description
  security_enabled = true
  owners           = local.owner_ids

  lifecycle {
    ignore_changes = [
      members, # Allow owners to manage membership
    ]
  }
}

output "group_ids" {
  description = "Map of group suffix to object ID"
  value       = { for k, g in azuread_group.groups : k => g.object_id }
}

output "group_names" {
  description = "Map of group suffix to display name"
  value       = { for k, g in azuread_group.groups : k => g.display_name }
}

output "groups" {
  description = "Full group details"
  value = { for k, g in azuread_group.groups : k => {
    id           = g.object_id
    display_name = g.display_name
    description  = g.description
  } }
}
