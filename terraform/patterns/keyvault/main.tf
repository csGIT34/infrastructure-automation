# terraform/patterns/keyvault/main.tf
# Key Vault Pattern - Secure secrets management with RBAC and access reviews

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
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
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
# Variables (from resolved pattern config)
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
  description = "Resource name suffix"
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
  default     = "keyvault"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

# Sizing-resolved config
variable "sku" {
  description = "Key Vault SKU (standard or premium)"
  type        = string
  default     = "standard"
}

# Note: soft_delete and purge_protection are hardcoded in the keyvault module
# (soft_delete=7 days minimum required by Azure, purge_protection=false)

variable "purge_protection" {
  description = "Ignored - purge protection is always disabled"
  type        = bool
  default     = false
}

# Pattern-specific config (optional features)
variable "access_reviewers" {
  description = "Email addresses of access reviewers (for prod)"
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

variable "geo_redundant_backup" {
  description = "Enable geo-redundant backup (not applicable to Key Vault, ignored)"
  type        = bool
  default     = false
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
  description = "Log Analytics workspace ID for diagnostics"
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
# Key Vault (base module)
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
    sku            = var.sku
    rbac_enabled   = true
    default_action = var.enable_private_endpoint ? "Deny" : "Allow"
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
      suffix      = "secrets-readers"
      description = "Read-only access to ${var.name} Key Vault secrets"
    },
    {
      suffix      = "secrets-admins"
      description = "Full access to ${var.name} Key Vault secrets"
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
      principal_id         = module.security_groups.group_ids["secrets-readers"]
      role_definition_name = "Key Vault Secrets User"
      scope                = module.keyvault.vault_id
      description          = "Readers group - secrets read access"
    },
    {
      principal_id         = module.security_groups.group_ids["secrets-admins"]
      role_definition_name = "Key Vault Secrets Officer"
      scope                = module.keyvault.vault_id
      description          = "Admins group - secrets management"
    }
  ]
}

# -----------------------------------------------------------------------------
# Access Review (two-stage: group owners -> manager)
# -----------------------------------------------------------------------------
resource "time_static" "access_review_start" {
  count = var.enable_access_review ? 1 : 0
}

module "access_review" {
  source = "../../modules/access-review"
  count  = var.enable_access_review ? 1 : 0

  group_id   = module.security_groups.group_ids["secrets-admins"]
  group_name = module.security_groups.group_names["secrets-admins"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", time_static.access_review_start[0].rfc3339)
}

# -----------------------------------------------------------------------------
# Diagnostic Settings (staging/prod)
# -----------------------------------------------------------------------------
module "diagnostics" {
  source = "../../modules/diagnostic-settings"
  count  = var.enable_diagnostics && var.log_analytics_workspace_id != "" ? 1 : 0

  name                       = module.keyvault_naming.name
  target_resource_id         = module.keyvault.vault_id
  log_analytics_workspace_id = var.log_analytics_workspace_id
  logs                       = ["AuditEvent", "AzurePolicyEvaluationDetails"]
  metrics                    = ["AllMetrics"]
}

# -----------------------------------------------------------------------------
# Private Endpoint (optional)
# -----------------------------------------------------------------------------
data "azurerm_private_dns_zone" "keyvault" {
  count               = var.enable_private_endpoint && var.subnet_id != "" ? 1 : 0
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = "rg-dns-${var.environment}"
}

module "private_endpoint" {
  source = "../../modules/private-endpoint"
  count  = var.enable_private_endpoint && var.subnet_id != "" ? 1 : 0

  name                = module.keyvault_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = var.subnet_id
  target_resource_id  = module.keyvault.vault_id
  subresource_names   = ["vault"]
  dns_zone_id         = data.azurerm_private_dns_zone.keyvault[0].id
  tags                = module.naming.tags
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "keyvault" {
  description = "Key Vault details"
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

output "access_info" {
  description = "Access information for developers"
  value       = <<-EOT
    Key Vault: ${module.keyvault.vault_name}
    URI: ${module.keyvault.vault_uri}

    Security Groups:
    - Readers: ${module.security_groups.group_names["secrets-readers"]}
    - Admins: ${module.security_groups.group_names["secrets-admins"]}

    To access secrets:
      az keyvault secret show --vault-name ${module.keyvault.vault_name} --name <secret-name>
  EOT
}

output "private_endpoint_ip" {
  description = "Private endpoint IP address"
  value       = var.enable_private_endpoint && var.subnet_id != "" ? module.private_endpoint[0].private_ip : null
}
