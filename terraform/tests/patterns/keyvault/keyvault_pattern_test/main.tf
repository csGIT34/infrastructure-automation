# Test fixture: Keyvault pattern
#
# Replicates the keyvault pattern composition for testing.

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
  description = "Owner email for security groups"
  type        = string
}


locals {
  project       = "tftest-${var.resource_suffix}"
  environment   = "dev"
  name          = "kv"
  business_unit = "engineering"
  pattern_name  = "keyvault"
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

# Key Vault
module "keyvault_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "keyvault"
  name          = local.name
  business_unit = local.business_unit
  pattern_name  = local.pattern_name
}

module "keyvault" {
  source = "../../../../modules/keyvault"

  name                = module.keyvault_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku            = "standard"
    rbac_enabled   = true
    default_action = "Allow"
  }
  tags = module.naming.tags
}

# Security Groups
module "security_groups" {
  source = "../../../../modules/security-groups"

  project     = local.project
  environment = local.environment
  groups = [
    {
      suffix      = "secrets-readers"
      description = "Read-only access to Key Vault secrets (test)"
    },
    {
      suffix      = "secrets-admins"
      description = "Full access to Key Vault secrets (test)"
    }
  ]
  owner_emails = [var.owner_email]
}

# RBAC Assignments
module "rbac" {
  source = "../../../../modules/rbac-assignments"

  assignments = [
    {
      principal_id         = module.security_groups.group_ids["secrets-readers"]
      role_definition_name = "Key Vault Secrets User"
      scope                = module.keyvault.vault_id
      description          = "Readers - secrets read access (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["secrets-admins"]
      role_definition_name = "Key Vault Secrets Officer"
      scope                = module.keyvault.vault_id
      description          = "Admins - secrets management (test)"
    }
  ]
}

# Access Reviews for Security Groups
module "access_review_readers" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["secrets-readers"]
  group_name = module.security_groups.group_names["secrets-readers"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

module "access_review_admins" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["secrets-admins"]
  group_name = module.security_groups.group_names["secrets-admins"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

# Outputs
output "keyvault" {
  value = {
    name = module.keyvault.vault_name
    uri  = module.keyvault.vault_uri
    id   = module.keyvault.vault_id
  }
}

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "security_groups" {
  value = module.security_groups.group_names
}

output "access_reviews" {
  value = {
    readers = module.access_review_readers.review_name
    admins  = module.access_review_admins.review_name
  }
}

output "access_info" {
  value = <<-EOT
    Key Vault: ${module.keyvault.vault_name}
    URI: ${module.keyvault.vault_uri}

    Security Groups:
    - Readers: ${module.security_groups.group_names["secrets-readers"]}
    - Admins: ${module.security_groups.group_names["secrets-admins"]}

    Access Reviews:
    - ${module.access_review_readers.review_name}
    - ${module.access_review_admins.review_name}
  EOT
}
