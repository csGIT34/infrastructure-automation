# Test fixture: SQL Database pattern
#
# Replicates the sql-database pattern composition for testing:
# Azure SQL Server + Database + Key Vault + Security Groups + RBAC + Access Reviews

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
  description = "Owner email for security groups"
  type        = string
}

locals {
  project       = "tftest-${var.resource_suffix}"
  environment   = "dev"
  name          = "sqldb"
  business_unit = "engineering"
  pattern_name  = "sql-database"
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

# Azure SQL Server and Database
module "sql_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "azure_sql"
  name          = local.name
  business_unit = local.business_unit
}

module "azure_sql" {
  source = "../../../../modules/azure-sql"

  name                = module.sql_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku_name       = "Basic"
    max_size_gb    = 2
    zone_redundant = false
  }
  tags = module.naming.tags
}

# Key Vault for connection secrets
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
    sku          = "standard"
    rbac_enabled = true
  }
  secrets = module.azure_sql.secrets_for_keyvault
  tags    = module.naming.tags
}

# Security Groups
module "security_groups" {
  source = "../../../../modules/security-groups"

  project     = local.project
  environment = local.environment
  groups = [
    {
      suffix      = "sql-readers"
      description = "Read access to ${local.name} SQL connection info (test)"
    },
    {
      suffix      = "sql-admins"
      description = "Admin access to ${local.name} SQL database (test)"
    }
  ]
  owner_emails = [var.owner_email]
}

# RBAC Assignments
module "rbac" {
  source = "../../../../modules/rbac-assignments"

  assignments = [
    {
      principal_id         = module.security_groups.group_ids["sql-readers"]
      role_definition_name = "Key Vault Secrets User"
      scope                = module.keyvault.vault_id
      description          = "SQL readers - connection string access (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["sql-admins"]
      role_definition_name = "Key Vault Secrets Officer"
      scope                = module.keyvault.vault_id
      description          = "SQL admins - secrets management (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["sql-admins"]
      role_definition_name = "SQL DB Contributor"
      scope                = module.azure_sql.databases["default"].id
      description          = "SQL admins - database management (test)"
    }
  ]
}

# Access Reviews for Security Groups
module "access_review_readers" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["sql-readers"]
  group_name = module.security_groups.group_names["sql-readers"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

module "access_review_admins" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["sql-admins"]
  group_name = module.security_groups.group_names["sql-admins"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

# Outputs
output "sql_database" {
  description = "SQL Database details"
  value = {
    server_fqdn   = module.azure_sql.server_fqdn
    database_name = module.azure_sql.database_name
    server_id     = module.azure_sql.server_id
    database_id   = module.azure_sql.databases["default"].id
  }
}

output "keyvault" {
  description = "Key Vault for connection secrets"
  value = {
    name = module.keyvault.vault_name
    uri  = module.keyvault.vault_uri
    id   = module.keyvault.vault_id
  }
}

output "resource_group" {
  description = "Resource group name"
  value       = azurerm_resource_group.main.name
}

output "security_groups" {
  description = "Security group names"
  value       = module.security_groups.group_names
}

output "access_reviews" {
  description = "Access review names"
  value = {
    readers = module.access_review_readers.review_name
    admins  = module.access_review_admins.review_name
  }
}

output "access_info" {
  description = "Access information for developers"
  value       = <<-EOT
    SQL Database Pattern Test Results
    ==================================

    SQL Server: ${module.azure_sql.server_fqdn}
    Database: ${module.azure_sql.database_name}

    Connection secrets stored in: ${module.keyvault.vault_name}
    Key Vault URI: ${module.keyvault.vault_uri}

    Security Groups:
    - Readers: ${module.security_groups.group_names["sql-readers"]}
    - Admins: ${module.security_groups.group_names["sql-admins"]}

    Access Reviews:
    - ${module.access_review_readers.review_name}
    - ${module.access_review_admins.review_name}

    To get connection string:
      az keyvault secret show --vault-name ${module.keyvault.vault_name} --name sql-connection-string-default --query value -o tsv
  EOT
}
