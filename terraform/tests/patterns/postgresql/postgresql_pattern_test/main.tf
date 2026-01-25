# Test fixture: PostgreSQL pattern
#
# Replicates the postgresql pattern composition for testing.

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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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
  name          = "pg"
  business_unit = "engineering"
  pattern_name  = "postgresql"
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

# PostgreSQL
module "postgresql_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "postgresql"
  name          = local.name
  business_unit = local.business_unit
}

module "postgresql" {
  source = "../../../../modules/postgresql"

  name                = module.postgresql_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku                   = "B_Standard_B1ms"
    storage_mb            = 32768
    version               = "14"
    backup_retention_days = 7
    geo_redundant_backup  = false
  }
  tags = module.naming.tags
}

# Key Vault for secrets
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
  secrets = {
    "postgresql-connection-string" = "Host=${module.postgresql.server_fqdn};Database=${module.postgresql.database_name};Username=psqladmin"
    "postgresql-server-fqdn"       = module.postgresql.server_fqdn
    "postgresql-database-name"     = module.postgresql.database_name
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
      suffix      = "db-readers"
      description = "Read access to ${local.name} PostgreSQL connection info (test)"
    },
    {
      suffix      = "db-admins"
      description = "Admin access to ${local.name} PostgreSQL (test)"
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
      principal_id         = module.security_groups.group_ids["db-readers"]
      role_definition_name = "Key Vault Secrets User"
      scope                = module.keyvault.vault_id
      description          = "DB readers - secrets read access (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["db-admins"]
      role_definition_name = "Key Vault Secrets Officer"
      scope                = module.keyvault.vault_id
      description          = "DB admins - secrets management (test)"
    }
  ]
}

# Access Reviews for Security Groups
module "access_review_readers" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["db-readers"]
  group_name = module.security_groups.group_names["db-readers"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

module "access_review_admins" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["db-admins"]
  group_name = module.security_groups.group_names["db-admins"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

# Outputs
output "postgresql" {
  value = {
    server_fqdn   = module.postgresql.server_fqdn
    database_name = module.postgresql.database_name
    server_id     = module.postgresql.server_id
  }
}

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
    PostgreSQL Server: ${module.postgresql.server_fqdn}
    Database: ${module.postgresql.database_name}

    Connection secrets stored in: ${module.keyvault.vault_name}
    Secret names:
    - postgresql-connection-string
    - postgresql-server-fqdn
    - postgresql-database-name

    Security Groups:
    - Readers: ${module.security_groups.group_names["db-readers"]}
    - Admins: ${module.security_groups.group_names["db-admins"]}

    Access Reviews:
    - ${module.access_review_readers.review_name}
    - ${module.access_review_admins.review_name}
  EOT
}
