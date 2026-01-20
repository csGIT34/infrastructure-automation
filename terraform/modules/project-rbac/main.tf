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
# Groups are only created if there are resources that need them.
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

# Deployable resources (deployers group)
variable "function_app_ids" {
    description = "Map of Function App IDs for deployer RBAC"
    type        = map(string)
    default     = {}
}

variable "static_web_app_ids" {
    description = "Map of Static Web App IDs for deployer RBAC"
    type        = map(string)
    default     = {}
}

variable "aks_namespace_ids" {
    description = "Map of AKS namespace identifiers for deployer RBAC"
    type        = map(string)
    default     = {}
}

# Data resources (data group)
variable "sql_server_ids" {
    description = "Map of Azure SQL Server IDs for data access RBAC"
    type        = map(string)
    default     = {}
}

variable "postgresql_server_ids" {
    description = "Map of PostgreSQL Server IDs for data access RBAC"
    type        = map(string)
    default     = {}
}

variable "cosmosdb_account_ids" {
    description = "Map of Cosmos DB (MongoDB) Account IDs for data access RBAC"
    type        = map(string)
    default     = {}
}

variable "storage_account_ids" {
    description = "Map of Storage Account IDs for data access RBAC"
    type        = map(string)
    default     = {}
}

variable "eventhub_namespace_ids" {
    description = "Map of Event Hub Namespace IDs for data access RBAC"
    type        = map(string)
    default     = {}
}

# Compute resources (compute group)
variable "linux_vm_ids" {
    description = "Map of Linux VM IDs for compute access RBAC"
    type        = map(string)
    default     = {}
}

variable "tags" {
    type    = map(string)
    default = {}
}

# Enable flags - computed in catalog from YAML (known at plan time)
variable "enable_secrets_group" {
    description = "Whether to create the secrets security group"
    type        = bool
    default     = true
}

variable "enable_deployers_group" {
    description = "Whether to create the deployers security group"
    type        = bool
    default     = false
}

variable "enable_data_group" {
    description = "Whether to create the data security group"
    type        = bool
    default     = false
}

variable "enable_compute_group" {
    description = "Whether to create the compute security group"
    type        = bool
    default     = false
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

    # Determine which groups are needed based on resources
    # Use boolean flags passed from catalog (computed from YAML, known at plan time)
    has_keyvault             = var.enable_secrets_group
    has_deployable_resources = var.enable_deployers_group
    has_data_resources       = var.enable_data_group
    has_compute_resources    = var.enable_compute_group

    # Build groups map conditionally
    groups = merge(
        # Readers group - always created (Reader on RG is always useful)
        {
            readers = {
                display_name = "${local.prefix}-readers"
                description  = "Read access to ${var.project_name} ${var.environment} resources"
            }
        },
        # Secrets group - only if Key Vault exists
        local.has_keyvault ? {
            secrets = {
                display_name = "${local.prefix}-secrets"
                description  = "Key Vault secrets access for ${var.project_name} ${var.environment}"
            }
        } : {},
        # Deployers group - only if there are deployable resources
        local.has_deployable_resources ? {
            deployers = {
                display_name = "${local.prefix}-deployers"
                description  = "Deployment access for ${var.project_name} ${var.environment}"
            }
        } : {},
        # Data group - only if there are data resources
        local.has_data_resources ? {
            data = {
                display_name = "${local.prefix}-data"
                description  = "Data store access for ${var.project_name} ${var.environment}"
            }
        } : {},
        # Compute group - only if there are VMs
        local.has_compute_resources ? {
            compute = {
                display_name = "${local.prefix}-compute"
                description  = "VM access for ${var.project_name} ${var.environment}"
            }
        } : {}
    )
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
# Groups are created conditionally based on resource presence.
# Owners can manage group membership - Terraform doesn't need GroupMember perms.

resource "azuread_group" "groups" {
    for_each = local.groups

    display_name     = each.value.display_name
    description      = each.value.description
    security_enabled = true

    # Set the specified users AND the Terraform SP as group owners
    # This allows the SP to add members, and users can manage membership too
    owners = concat(local.owner_ids, [data.azuread_client_config.current.object_id])

    # Add owners as initial members so they have access immediately
    members = local.owner_ids

    prevent_duplicate_names = true
}

# -----------------------------------------------------------------------------
# RBAC Role Assignments - Readers Group (always created)
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "readers_rg" {
    scope                = var.resource_group_id
    role_definition_name = "Reader"
    principal_id         = azuread_group.groups["readers"].object_id
}

# -----------------------------------------------------------------------------
# RBAC Role Assignments - Secrets Group (if Key Vault exists)
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "secrets_keyvault" {
    count = local.has_keyvault ? 1 : 0

    scope                = var.keyvault_id
    role_definition_name = "Key Vault Secrets User"
    principal_id         = azuread_group.groups["secrets"].object_id
}

# -----------------------------------------------------------------------------
# RBAC Role Assignments - Deployers Group (if deployable resources exist)
# -----------------------------------------------------------------------------

# Website Contributor on Function Apps
resource "azurerm_role_assignment" "deployers_function_apps" {
    for_each = local.has_deployable_resources ? var.function_app_ids : {}

    scope                = each.value
    role_definition_name = "Website Contributor"
    principal_id         = azuread_group.groups["deployers"].object_id
}

# Contributor on Static Web Apps (for deployment)
resource "azurerm_role_assignment" "deployers_static_web_apps" {
    for_each = local.has_deployable_resources ? var.static_web_app_ids : {}

    scope                = each.value
    role_definition_name = "Contributor"
    principal_id         = azuread_group.groups["deployers"].object_id
}

# Azure Kubernetes Service Cluster User Role for AKS namespaces
resource "azurerm_role_assignment" "deployers_aks" {
    for_each = local.has_deployable_resources ? var.aks_namespace_ids : {}

    scope                = each.value
    role_definition_name = "Azure Kubernetes Service Cluster User Role"
    principal_id         = azuread_group.groups["deployers"].object_id
}

# -----------------------------------------------------------------------------
# RBAC Role Assignments - Data Group (if data resources exist)
# -----------------------------------------------------------------------------

# SQL DB Contributor on Azure SQL Servers
resource "azurerm_role_assignment" "data_sql" {
    for_each = local.has_data_resources ? var.sql_server_ids : {}

    scope                = each.value
    role_definition_name = "SQL DB Contributor"
    principal_id         = azuread_group.groups["data"].object_id
}

# Contributor on PostgreSQL Servers
resource "azurerm_role_assignment" "data_postgresql" {
    for_each = local.has_data_resources ? var.postgresql_server_ids : {}

    scope                = each.value
    role_definition_name = "Contributor"
    principal_id         = azuread_group.groups["data"].object_id
}

# Cosmos DB Account Reader Role + Data Contributor
resource "azurerm_role_assignment" "data_cosmosdb" {
    for_each = local.has_data_resources ? var.cosmosdb_account_ids : {}

    scope                = each.value
    role_definition_name = "Cosmos DB Account Reader Role"
    principal_id         = azuread_group.groups["data"].object_id
}

resource "azurerm_role_assignment" "data_cosmosdb_data" {
    for_each = local.has_data_resources ? var.cosmosdb_account_ids : {}

    scope                = each.value
    role_definition_name = "Cosmos DB Built-in Data Contributor"
    principal_id         = azuread_group.groups["data"].object_id
}

# Storage Blob Data Contributor on Storage Accounts
resource "azurerm_role_assignment" "data_storage" {
    for_each = local.has_data_resources ? var.storage_account_ids : {}

    scope                = each.value
    role_definition_name = "Storage Blob Data Contributor"
    principal_id         = azuread_group.groups["data"].object_id
}

# Azure Event Hubs Data Owner on Event Hub Namespaces
resource "azurerm_role_assignment" "data_eventhub" {
    for_each = local.has_data_resources ? var.eventhub_namespace_ids : {}

    scope                = each.value
    role_definition_name = "Azure Event Hubs Data Owner"
    principal_id         = azuread_group.groups["data"].object_id
}

# -----------------------------------------------------------------------------
# RBAC Role Assignments - Compute Group (if VMs exist)
# -----------------------------------------------------------------------------

# Virtual Machine Contributor on Linux VMs
resource "azurerm_role_assignment" "compute_vm" {
    for_each = local.has_compute_resources ? var.linux_vm_ids : {}

    scope                = each.value
    role_definition_name = "Virtual Machine Contributor"
    principal_id         = azuread_group.groups["compute"].object_id
}

# Virtual Machine User Login for SSH access
resource "azurerm_role_assignment" "compute_vm_login" {
    for_each = local.has_compute_resources ? var.linux_vm_ids : {}

    scope                = each.value
    role_definition_name = "Virtual Machine User Login"
    principal_id         = azuread_group.groups["compute"].object_id
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "group_ids" {
    description = "Map of security group object IDs (only includes created groups)"
    value = { for k, v in azuread_group.groups : k => v.object_id }
}

output "group_names" {
    description = "Map of security group display names (only includes created groups)"
    value = { for k, v in azuread_group.groups : k => v.display_name }
}

output "groups_created" {
    description = "List of which groups were created"
    value       = keys(local.groups)
}
