terraform {
    required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = "~> 3.0"
        }
        azuread = {
            source  = "hashicorp/azuread"
            version = "~> 2.0"
        }
    }
}

# -----------------------------------------------------------------------------
# Project RBAC Module
# -----------------------------------------------------------------------------
# Creates Entra ID security groups with delegated ownership model.
#
# Required Graph API Permissions (least privilege):
#   - Group.Create          : Create security groups
#   - Group.Read.All        : Read group properties
#   - User.Read.All         : Look up users by email
#   - Application.Read.All  : Read application/service principal info
#
# The specified owners become GROUP OWNERS, allowing them to manage
# membership without Terraform needing GroupMember.ReadWrite.All
# -----------------------------------------------------------------------------

variable "project_name" {
    description = "Project name for resource naming"
    type        = string
}

variable "environment" {
    description = "Environment (dev, staging, prod)"
    type        = string
}

variable "owner_emails" {
    description = "List of user emails to be set as group owners"
    type        = list(string)
}

variable "resource_group_id" {
    description = "Resource group ID for RBAC assignments"
    type        = string
}

variable "keyvault_id" {
    description = "Key Vault ID for secrets access RBAC"
    type        = string
    default     = null
}

variable "function_app_ids" {
    description = "Map of Function App IDs for deployer RBAC"
    type        = map(string)
    default     = {}
}

variable "sql_server_ids" {
    description = "Map of SQL Server IDs for data access RBAC"
    type        = map(string)
    default     = {}
}

variable "storage_account_ids" {
    description = "Map of Storage Account IDs for data access RBAC"
    type        = map(string)
    default     = {}
}

variable "tags" {
    type    = map(string)
    default = {}
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "azuread_client_config" "current" {}

# Look up users by their email/UPN
data "azuread_user" "owners" {
    for_each            = toset(var.owner_emails)
    user_principal_name = each.value
}

locals {
    prefix    = "sg-${var.project_name}-${var.environment}"
    owner_ids = [for user in data.azuread_user.owners : user.object_id]

    # Security group definitions
    groups = {
        readers = {
            display_name = "${local.prefix}-readers"
            description  = "Read access to ${var.project_name} ${var.environment} resources"
        }
        secrets = {
            display_name = "${local.prefix}-secrets"
            description  = "Key Vault secrets access for ${var.project_name} ${var.environment}"
        }
        deployers = {
            display_name = "${local.prefix}-deployers"
            description  = "Deployment access for ${var.project_name} ${var.environment}"
        }
        data = {
            display_name = "${local.prefix}-data"
            description  = "Data store access for ${var.project_name} ${var.environment}"
        }
    }
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
# Groups are created with owners set to the specified users.
# Owners can manage group membership - Terraform doesn't need GroupMember perms.

resource "azuread_group" "groups" {
    for_each = local.groups

    display_name     = each.value.display_name
    description      = each.value.description
    security_enabled = true

    # Set the specified users as group owners
    # Owners can add/remove members without Terraform intervention
    owners = local.owner_ids

    # Also add owners as initial members so they have access immediately
    members = local.owner_ids

    prevent_duplicate_names = true
}

# -----------------------------------------------------------------------------
# RBAC Role Assignments - Readers Group
# -----------------------------------------------------------------------------
# Reader role on resource group - view all resources, logs, metrics

resource "azurerm_role_assignment" "readers_rg" {
    scope                = var.resource_group_id
    role_definition_name = "Reader"
    principal_id         = azuread_group.groups["readers"].object_id
}

# -----------------------------------------------------------------------------
# RBAC Role Assignments - Secrets Group
# -----------------------------------------------------------------------------
# Key Vault Secrets User - read secrets for local development

resource "azurerm_role_assignment" "secrets_keyvault" {
    count = var.keyvault_id != null ? 1 : 0

    scope                = var.keyvault_id
    role_definition_name = "Key Vault Secrets User"
    principal_id         = azuread_group.groups["secrets"].object_id
}

# -----------------------------------------------------------------------------
# RBAC Role Assignments - Deployers Group
# -----------------------------------------------------------------------------
# Website Contributor on Function Apps - deploy code

resource "azurerm_role_assignment" "deployers_function_apps" {
    for_each = var.function_app_ids

    scope                = each.value
    role_definition_name = "Website Contributor"
    principal_id         = azuread_group.groups["deployers"].object_id
}

# -----------------------------------------------------------------------------
# RBAC Role Assignments - Data Group
# -----------------------------------------------------------------------------
# SQL DB Contributor on SQL Servers

resource "azurerm_role_assignment" "data_sql" {
    for_each = var.sql_server_ids

    scope                = each.value
    role_definition_name = "SQL DB Contributor"
    principal_id         = azuread_group.groups["data"].object_id
}

# Storage Blob Data Contributor on Storage Accounts

resource "azurerm_role_assignment" "data_storage" {
    for_each = var.storage_account_ids

    scope                = each.value
    role_definition_name = "Storage Blob Data Contributor"
    principal_id         = azuread_group.groups["data"].object_id
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "group_ids" {
    description = "Map of security group object IDs"
    value = {
        readers   = azuread_group.groups["readers"].object_id
        secrets   = azuread_group.groups["secrets"].object_id
        deployers = azuread_group.groups["deployers"].object_id
        data      = azuread_group.groups["data"].object_id
    }
}

output "group_names" {
    description = "Map of security group display names"
    value = {
        readers   = azuread_group.groups["readers"].display_name
        secrets   = azuread_group.groups["secrets"].display_name
        deployers = azuread_group.groups["deployers"].display_name
        data      = azuread_group.groups["data"].display_name
    }
}
