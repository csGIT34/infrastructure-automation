# terraform/patterns/storage/main.tf
# Storage Pattern - Azure Storage Account with blob containers and RBAC

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    msgraph = {
      source  = "microsoft/msgraph"
      version = "~> 0.2"
    }
  }
  backend "azurerm" {
    use_oidc = true
  }
}

provider "azurerm" {
  features {}
  use_oidc = true
}

provider "azuread" {
  use_oidc = true
}

provider "msgraph" {
  use_oidc = true
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------
variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "name" {
  description = "Storage account name"
  type        = string
}

variable "owners" {
  description = "List of owner email addresses"
  type        = list(string)
}

variable "business_unit" {
  description = "Business unit for tagging"
  type        = string
}

variable "pattern_name" {
  description = "Pattern name for resource group naming"
  type        = string
  default     = "storage"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

# Sizing-resolved config
variable "account_tier" {
  description = "Storage account tier (Standard or Premium)"
  type        = string
  default     = "Standard"
}

variable "replication_type" {
  description = "Replication type (LRS, GRS, ZRS, RAGRS)"
  type        = string
  default     = "LRS"
}

variable "access_tier" {
  description = "Access tier (Hot, Cool, Archive)"
  type        = string
  default     = "Hot"
}

# Pattern-specific config
variable "containers" {
  description = "List of blob containers to create"
  type        = list(string)
  default     = []
}

variable "enable_diagnostics" {
  description = "Enable diagnostic settings"
  type        = bool
  default     = false
}

variable "enable_access_review" {
  description = "Enable Entra access reviews"
  type        = bool
  default     = false
}

variable "purge_protection" {
  description = "Enable purge protection (not applicable, ignored)"
  type        = bool
  default     = false
}

variable "geo_redundant_backup" {
  description = "Enable geo-redundant backup (not applicable, ignored)"
  type        = bool
  default     = false
}

variable "access_reviewers" {
  description = "Email addresses of access reviewers"
  type        = list(string)
  default     = []
}

variable "enable_private_endpoint" {
  description = "Enable private endpoint"
  type        = bool
  default     = false
}

variable "subnet_id" {
  description = "Subnet ID for private endpoint"
  type        = string
  default     = ""
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------
module "naming" {
  source = "../../modules/naming"

  project       = var.project
  environment   = var.environment
  resource_type = "resource_group"
  name          = var.name
  business_unit = var.business_unit
  pattern_name  = var.pattern_name
}

resource "azurerm_resource_group" "main" {
  name     = module.naming.resource_group_name
  location = var.location
  tags     = module.naming.tags
}

# -----------------------------------------------------------------------------
# Storage Account
# -----------------------------------------------------------------------------
module "storage_naming" {
  source = "../../modules/naming"

  project       = var.project
  environment   = var.environment
  resource_type = "storage_account"
  name          = var.name
  business_unit = var.business_unit
}

resource "azurerm_storage_account" "main" {
  name                     = module.storage_naming.name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.account_tier
  account_replication_type = var.replication_type
  access_tier              = var.access_tier
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = var.environment == "prod"

    dynamic "delete_retention_policy" {
      for_each = var.environment != "dev" ? [1] : []
      content {
        days = var.environment == "prod" ? 30 : 7
      }
    }
  }

  tags = module.naming.tags
}

# Blob containers
resource "azurerm_storage_container" "containers" {
  for_each = toset(var.containers)

  name                  = each.value
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
module "security_groups" {
  source = "../../modules/security-groups"

  project     = var.project
  environment = var.environment
  groups = [
    {
      suffix      = "storage-readers"
      description = "Read access to ${var.name} storage"
    },
    {
      suffix      = "storage-contributors"
      description = "Read/write access to ${var.name} storage"
    }
  ]
  owner_emails = var.owners
}

# -----------------------------------------------------------------------------
# RBAC Assignments
# -----------------------------------------------------------------------------
module "rbac" {
  source = "../../modules/rbac-assignments"

  assignments = [
    {
      principal_id         = module.security_groups.group_ids["storage-readers"]
      role_definition_name = "Storage Blob Data Reader"
      scope                = azurerm_storage_account.main.id
      description          = "Storage readers - blob read access"
    },
    {
      principal_id         = module.security_groups.group_ids["storage-contributors"]
      role_definition_name = "Storage Blob Data Contributor"
      scope                = azurerm_storage_account.main.id
      description          = "Storage contributors - blob read/write"
    }
  ]
}

# -----------------------------------------------------------------------------
# Network Rules
# -----------------------------------------------------------------------------
module "network_rules" {
  source = "../../modules/network-rules"
  count  = var.enable_private_endpoint ? 1 : 0

  resource_type         = "storage"
  resource_id           = azurerm_storage_account.main.id
  default_action        = "Deny"
  bypass_azure_services = true
}

# -----------------------------------------------------------------------------
# Diagnostic Settings
# -----------------------------------------------------------------------------
module "diagnostics" {
  source = "../../modules/diagnostic-settings"
  count  = var.enable_diagnostics && var.log_analytics_workspace_id != "" ? 1 : 0

  name                       = module.storage_naming.name
  target_resource_id         = "${azurerm_storage_account.main.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace_id
  logs                       = ["StorageRead", "StorageWrite", "StorageDelete"]
  metrics                    = ["Transaction"]
}

# -----------------------------------------------------------------------------
# Private Endpoint
# -----------------------------------------------------------------------------
data "azurerm_private_dns_zone" "storage" {
  count               = var.enable_private_endpoint && var.subnet_id != "" ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = "rg-dns-${var.environment}"
}

module "private_endpoint" {
  source = "../../modules/private-endpoint"
  count  = var.enable_private_endpoint && var.subnet_id != "" ? 1 : 0

  name                = module.storage_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = var.subnet_id
  target_resource_id  = azurerm_storage_account.main.id
  subresource_names   = ["blob"]
  dns_zone_id         = data.azurerm_private_dns_zone.storage[0].id
  tags                = module.naming.tags
}

# -----------------------------------------------------------------------------
# Access Review (prod only)
# -----------------------------------------------------------------------------
module "access_review" {
  source = "../../modules/access-review"
  count  = var.enable_access_review ? 1 : 0

  group_id   = module.security_groups.group_ids["storage-contributors"]
  group_name = module.security_groups.group_names["storage-contributors"]
  frequency  = "quarterly"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "storage_account" {
  description = "Storage account details"
  value = {
    name                = azurerm_storage_account.main.name
    id                  = azurerm_storage_account.main.id
    primary_blob_endpoint = azurerm_storage_account.main.primary_blob_endpoint
  }
}

output "containers" {
  description = "Created containers"
  value       = [for c in azurerm_storage_container.containers : c.name]
}

output "resource_group" {
  description = "Resource group name"
  value       = azurerm_resource_group.main.name
}

output "security_groups" {
  description = "Security group names"
  value       = module.security_groups.group_names
}

output "access_info" {
  description = "Access information for developers"
  value       = <<-EOT
    Storage Account: ${azurerm_storage_account.main.name}
    Blob Endpoint: ${azurerm_storage_account.main.primary_blob_endpoint}

    Containers: ${join(", ", [for c in azurerm_storage_container.containers : c.name])}

    Security Groups:
    - Readers: ${module.security_groups.group_names["storage-readers"]}
    - Contributors: ${module.security_groups.group_names["storage-contributors"]}

    To list blobs:
      az storage blob list --account-name ${azurerm_storage_account.main.name} --container-name <container> --auth-mode login
  EOT
}
