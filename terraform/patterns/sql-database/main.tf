# terraform/patterns/sql-database/main.tf
# Azure SQL Database Pattern - Managed SQL Server with RBAC

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
  description = "Database name"
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
  default     = "sql-database"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

# Sizing-resolved config
variable "sku_name" {
  description = "SQL Database SKU"
  type        = string
  default     = "Basic"
}

variable "max_size_gb" {
  description = "Maximum database size in GB"
  type        = number
  default     = 2
}

variable "zone_redundant" {
  description = "Enable zone redundancy"
  type        = bool
  default     = false
}

# Pattern-specific config
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

variable "allowed_ips" {
  description = "Allowed IP addresses for firewall"
  type        = list(string)
  default     = []
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
# Azure SQL (base module)
# -----------------------------------------------------------------------------
module "sql_naming" {
  source = "../../modules/naming"

  project       = var.project
  environment   = var.environment
  resource_type = "azure_sql"
  name          = var.name
  business_unit = var.business_unit
}

module "azure_sql" {
  source = "../../modules/azure-sql"

  name                = module.sql_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku_name       = var.sku_name
    max_size_gb    = var.max_size_gb
    zone_redundant = var.zone_redundant
  }
  tags = module.naming.tags
}

# -----------------------------------------------------------------------------
# Key Vault for connection secrets
# -----------------------------------------------------------------------------
module "keyvault_naming" {
  source = "../../modules/naming"

  project       = var.project
  environment   = var.environment
  resource_type = "keyvault"
  name          = var.name
  business_unit = var.business_unit
  pattern_name  = var.pattern_name
}

module "keyvault" {
  source = "../../modules/keyvault"

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

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------
module "security_groups" {
  source = "../../modules/security-groups"

  project     = var.project
  environment = var.environment
  groups = [
    {
      suffix      = "sql-readers"
      description = "Read access to ${var.name} SQL connection info"
    },
    {
      suffix      = "sql-admins"
      description = "Admin access to ${var.name} SQL database"
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
      principal_id         = module.security_groups.group_ids["sql-readers"]
      role_definition_name = "Key Vault Secrets User"
      scope                = module.keyvault.vault_id
      description          = "SQL readers - connection string access"
    },
    {
      principal_id         = module.security_groups.group_ids["sql-admins"]
      role_definition_name = "Key Vault Secrets Officer"
      scope                = module.keyvault.vault_id
      description          = "SQL admins - secrets management"
    },
    {
      principal_id         = module.security_groups.group_ids["sql-admins"]
      role_definition_name = "SQL DB Contributor"
      scope                = module.azure_sql.database_id
      description          = "SQL admins - database management"
    }
  ]
}

# -----------------------------------------------------------------------------
# Network Rules
# -----------------------------------------------------------------------------
module "network_rules" {
  source = "../../modules/network-rules"
  count  = length(var.allowed_ips) > 0 ? 1 : 0

  resource_type         = "azure_sql"
  resource_id           = module.azure_sql.server_id
  allowed_ips           = var.allowed_ips
  bypass_azure_services = true
}

# -----------------------------------------------------------------------------
# Diagnostic Settings
# -----------------------------------------------------------------------------
module "diagnostics" {
  source = "../../modules/diagnostic-settings"
  count  = var.enable_diagnostics && var.log_analytics_workspace_id != "" ? 1 : 0

  name                       = module.sql_naming.name
  target_resource_id         = module.azure_sql.database_id
  log_analytics_workspace_id = var.log_analytics_workspace_id
  logs                       = ["SQLInsights", "AutomaticTuning", "QueryStoreRuntimeStatistics"]
  metrics                    = ["Basic", "InstanceAndAppAdvanced"]
}

# -----------------------------------------------------------------------------
# Access Review (prod only)
# -----------------------------------------------------------------------------
module "access_review" {
  source = "../../modules/access-review"
  count  = var.enable_access_review && length(var.access_reviewers) > 0 ? 1 : 0

  group_id        = module.security_groups.group_ids["sql-admins"]
  group_name      = module.security_groups.group_names["sql-admins"]
  reviewer_emails = var.access_reviewers
  frequency       = "quarterly"
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "sql_database" {
  description = "SQL Database details"
  value = {
    server_fqdn   = module.azure_sql.server_fqdn
    database_name = module.azure_sql.database_name
    server_id     = module.azure_sql.server_id
    database_id   = module.azure_sql.database_id
  }
}

output "keyvault" {
  description = "Key Vault for connection secrets"
  value = {
    name = module.keyvault.vault_name
    uri  = module.keyvault.vault_uri
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

output "access_info" {
  description = "Access information for developers"
  value       = <<-EOT
    SQL Server: ${module.azure_sql.server_fqdn}
    Database: ${module.azure_sql.database_name}

    Connection secrets stored in: ${module.keyvault.vault_name}

    Security Groups:
    - Readers: ${module.security_groups.group_names["sql-readers"]}
    - Admins: ${module.security_groups.group_names["sql-admins"]}

    To get connection string:
      az keyvault secret show --vault-name ${module.keyvault.vault_name} --name sql-connection-string --query value -o tsv
  EOT
}
