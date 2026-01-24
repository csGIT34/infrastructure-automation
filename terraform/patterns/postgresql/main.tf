# terraform/patterns/postgresql/main.tf
# PostgreSQL Pattern - Managed PostgreSQL database with RBAC and secrets management

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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

# Sizing-resolved config
variable "sku" {
  description = "PostgreSQL SKU"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_mb" {
  description = "Storage size in MB"
  type        = number
  default     = 32768
}

variable "version" {
  description = "PostgreSQL version"
  type        = string
  default     = "14"
}

variable "backup_retention_days" {
  description = "Backup retention days"
  type        = number
  default     = 7
}

variable "geo_redundant_backup" {
  description = "Enable geo-redundant backup"
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

variable "allowed_ips" {
  description = "List of allowed IP addresses"
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
}

resource "azurerm_resource_group" "main" {
  name     = module.naming.resource_group_name
  location = var.location
  tags     = module.naming.tags
}

# -----------------------------------------------------------------------------
# PostgreSQL (base module)
# -----------------------------------------------------------------------------
module "postgresql_naming" {
  source = "../../modules/naming"

  project       = var.project
  environment   = var.environment
  resource_type = "postgresql"
  name          = var.name
  business_unit = var.business_unit
}

module "postgresql" {
  source = "../../modules/postgresql"

  name                = module.postgresql_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku                  = var.sku
    storage_mb           = var.storage_mb
    version              = var.version
    backup_retention_days = var.backup_retention_days
    geo_redundant_backup  = var.geo_redundant_backup
  }
  tags = module.naming.tags
}

# -----------------------------------------------------------------------------
# Key Vault for secrets
# -----------------------------------------------------------------------------
module "keyvault_naming" {
  source = "../../modules/naming"

  project       = var.project
  environment   = var.environment
  resource_type = "keyvault"
  name          = var.name
  business_unit = var.business_unit
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
  secrets = {
    "postgresql-connection-string" = "Host=${module.postgresql.server_fqdn};Database=${module.postgresql.database_name};Username=psqladmin"
    "postgresql-server-fqdn"       = module.postgresql.server_fqdn
    "postgresql-database-name"     = module.postgresql.database_name
  }
  tags = module.naming.tags
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
      suffix      = "db-readers"
      description = "Read access to ${var.name} PostgreSQL connection info"
    },
    {
      suffix      = "db-admins"
      description = "Admin access to ${var.name} PostgreSQL"
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
      principal_id         = module.security_groups.group_ids["db-readers"]
      role_definition_name = "Key Vault Secrets User"
      scope                = module.keyvault.vault_id
      description          = "DB readers - secrets read access"
    },
    {
      principal_id         = module.security_groups.group_ids["db-admins"]
      role_definition_name = "Key Vault Secrets Officer"
      scope                = module.keyvault.vault_id
      description          = "DB admins - secrets management"
    }
  ]
}

# -----------------------------------------------------------------------------
# Network Rules
# -----------------------------------------------------------------------------
module "network_rules" {
  source = "../../modules/network-rules"
  count  = length(var.allowed_ips) > 0 ? 1 : 0

  resource_type         = "postgresql"
  resource_id           = module.postgresql.server_id
  allowed_ips           = var.allowed_ips
  bypass_azure_services = true
}

# -----------------------------------------------------------------------------
# Diagnostic Settings
# -----------------------------------------------------------------------------
module "diagnostics" {
  source = "../../modules/diagnostic-settings"
  count  = var.enable_diagnostics && var.log_analytics_workspace_id != "" ? 1 : 0

  name                       = module.postgresql_naming.name
  target_resource_id         = module.postgresql.server_id
  log_analytics_workspace_id = var.log_analytics_workspace_id
  logs                       = ["PostgreSQLLogs", "QueryStoreRuntimeStatistics", "QueryStoreWaitStatistics"]
  metrics                    = ["AllMetrics"]
}

# -----------------------------------------------------------------------------
# Access Review (prod only)
# -----------------------------------------------------------------------------
module "access_review" {
  source = "../../modules/access-review"
  count  = var.enable_access_review && length(var.access_reviewers) > 0 ? 1 : 0

  group_id        = module.security_groups.group_ids["db-admins"]
  group_name      = module.security_groups.group_names["db-admins"]
  reviewer_emails = var.access_reviewers
  frequency       = "quarterly"
}

# -----------------------------------------------------------------------------
# Private Endpoint
# -----------------------------------------------------------------------------
data "azurerm_private_dns_zone" "postgresql" {
  count               = var.enable_private_endpoint && var.subnet_id != "" ? 1 : 0
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = "rg-dns-${var.environment}"
}

module "private_endpoint" {
  source = "../../modules/private-endpoint"
  count  = var.enable_private_endpoint && var.subnet_id != "" ? 1 : 0

  name                = module.postgresql_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = var.subnet_id
  target_resource_id  = module.postgresql.server_id
  subresource_names   = ["postgresqlServer"]
  dns_zone_id         = data.azurerm_private_dns_zone.postgresql[0].id
  tags                = module.naming.tags
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "postgresql" {
  description = "PostgreSQL server details"
  value = {
    server_fqdn   = module.postgresql.server_fqdn
    database_name = module.postgresql.database_name
    server_id     = module.postgresql.server_id
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

    To get connection string:
      az keyvault secret show --vault-name ${module.keyvault.vault_name} --name postgresql-connection-string --query value -o tsv
  EOT
}
