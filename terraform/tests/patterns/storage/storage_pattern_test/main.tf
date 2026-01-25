# Test fixture: Storage pattern
#
# Replicates the storage pattern composition for testing.

terraform {
  required_version = ">= 1.6.0"
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
}

variable "resource_suffix" {
  type = string
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "owner_email" {
  description = "Owner email for security groups (optional for tests)"
  type        = string
  default     = ""
}


locals {
  project       = "tftest-${var.resource_suffix}"
  environment   = "dev"
  name          = "st"
  business_unit = "engineering"
  pattern_name  = "storage"
}

# Resource Group
module "naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "resource_group"
  name          = local.name
  business_unit = local.business_unit
  pattern_name  = local.pattern_name
}

resource "azurerm_resource_group" "main" {
  name     = module.naming.resource_group_name
  location = var.location
  tags     = module.naming.tags
}

# Storage Account
module "storage_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "storage_account"
  name          = local.name
  business_unit = local.business_unit
  pattern_name  = local.pattern_name
}

resource "azurerm_storage_account" "main" {
  name                     = module.storage_naming.name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = false  # dev environment
  }

  tags = module.naming.tags
}

# Blob containers for testing
resource "azurerm_storage_container" "data" {
  name                  = "data"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

resource "azurerm_storage_container" "logs" {
  name                  = "logs"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}

# Security Groups
module "security_groups" {
  source = "../../../../modules/security-groups"

  project     = local.project
  environment = local.environment
  groups = [
    {
      suffix      = "storage-readers"
      description = "Read access to storage (test)"
    },
    {
      suffix      = "storage-contributors"
      description = "Read/write access to storage (test)"
    }
  ]
  # Only pass owner_emails if owner_email is set, otherwise empty list
  owner_emails = var.owner_email != "" ? [var.owner_email] : []
}

# RBAC Assignments
module "rbac" {
  source = "../../../../modules/rbac-assignments"

  assignments = [
    {
      principal_id         = module.security_groups.group_ids["storage-readers"]
      role_definition_name = "Storage Blob Data Reader"
      scope                = azurerm_storage_account.main.id
      description          = "Storage readers - blob read access (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["storage-contributors"]
      role_definition_name = "Storage Blob Data Contributor"
      scope                = azurerm_storage_account.main.id
      description          = "Storage contributors - blob read/write (test)"
    }
  ]
}

# Access Reviews for Security Groups
module "access_review_readers" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["storage-readers"]
  group_name = module.security_groups.group_names["storage-readers"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

module "access_review_contributors" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["storage-contributors"]
  group_name = module.security_groups.group_names["storage-contributors"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

# Outputs
output "storage_account" {
  value = {
    name                  = azurerm_storage_account.main.name
    id                    = azurerm_storage_account.main.id
    primary_blob_endpoint = azurerm_storage_account.main.primary_blob_endpoint
  }
}

output "containers" {
  value = [azurerm_storage_container.data.name, azurerm_storage_container.logs.name]
}

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "security_groups" {
  value = module.security_groups.group_names
}

output "access_reviews" {
  value = {
    readers      = module.access_review_readers.review_name
    contributors = module.access_review_contributors.review_name
  }
}

output "access_info" {
  value = <<-EOT
    Storage Account: ${azurerm_storage_account.main.name}
    Blob Endpoint: ${azurerm_storage_account.main.primary_blob_endpoint}

    Containers: data, logs

    Security Groups:
    - Readers: ${module.security_groups.group_names["storage-readers"]}
    - Contributors: ${module.security_groups.group_names["storage-contributors"]}

    Access Reviews:
    - ${module.access_review_readers.review_name}
    - ${module.access_review_contributors.review_name}
  EOT
}
