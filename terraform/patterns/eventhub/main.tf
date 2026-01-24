# terraform/patterns/eventhub/main.tf
# Event Hub Pattern - Azure Event Hubs for event streaming

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = ">= 4.0" }
    azuread = { source = "hashicorp/azuread", version = "~> 2.0" }
  }
  backend "azurerm" { use_oidc = true }
}

provider "azurerm" {
  features {}
  use_oidc = true
}
provider "azuread" { use_oidc = true }

# Variables
variable "project" { type = string }
variable "environment" { type = string }
variable "name" { type = string }
variable "owners" { type = list(string) }
variable "business_unit" { type = string }
variable "location" {
  type    = string
  default = "eastus"
}

variable "pattern_name" {
  description = "Pattern name for resource group naming"
  type        = string
  default     = "eventhub"
}

variable "sku" {
  type    = string
  default = "Basic"
}
variable "capacity" {
  type    = number
  default = 1
}
variable "partition_count" {
  type    = number
  default = 2
}
variable "message_retention" {
  type    = number
  default = 1
}

variable "enable_diagnostics" {
  type    = bool
  default = false
}
variable "enable_access_review" {
  type    = bool
  default = false
}
variable "purge_protection" {
  type    = bool
  default = false
}
variable "geo_redundant_backup" {
  type    = bool
  default = false
}
variable "access_reviewers" {
  type    = list(string)
  default = []
}
variable "log_analytics_workspace_id" {
  type    = string
  default = ""
}

# Resource Group
module "naming" {
  source        = "../../modules/naming"
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

# Event Hub
module "eventhub_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "eventhub"
  name          = var.name
  business_unit = var.business_unit
}

module "eventhub" {
  source = "../../modules/eventhub"

  name                = module.eventhub_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku               = var.sku
    capacity          = var.capacity
    partition_count   = var.partition_count
    message_retention = var.message_retention
  }
  tags = module.naming.tags
}

# Key Vault
module "keyvault_naming" {
  source        = "../../modules/naming"
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
  config = { sku = "standard", rbac_enabled = true }
  secrets = {
    "eventhub-connection-string" = module.eventhub.connection_string
    "eventhub-namespace"         = module.eventhub.namespace_name
  }
  tags = module.naming.tags
}

# Security Groups
module "security_groups" {
  source       = "../../modules/security-groups"
  project      = var.project
  environment  = var.environment
  groups = [
    { suffix = "eventhub-senders", description = "Send events to ${var.name}" },
    { suffix = "eventhub-receivers", description = "Receive events from ${var.name}" }
  ]
  owner_emails = var.owners
}

# RBAC
module "rbac" {
  source = "../../modules/rbac-assignments"
  assignments = [
    {
      principal_id         = module.security_groups.group_ids["eventhub-senders"]
      role_definition_name = "Azure Event Hubs Data Sender"
      scope                = module.eventhub.namespace_id
    },
    {
      principal_id         = module.security_groups.group_ids["eventhub-receivers"]
      role_definition_name = "Azure Event Hubs Data Receiver"
      scope                = module.eventhub.namespace_id
    }
  ]
}

# Access Review (prod only)
module "access_review" {
  source = "../../modules/access-review"
  count  = var.enable_access_review && length(var.access_reviewers) > 0 ? 1 : 0

  group_id        = module.security_groups.group_ids["eventhub-senders"]
  group_name      = module.security_groups.group_names["eventhub-senders"]
  reviewer_emails = var.access_reviewers
  frequency       = "quarterly"
}

# Diagnostics (staging/prod)
module "diagnostics" {
  source = "../../modules/diagnostic-settings"
  count  = var.enable_diagnostics && var.log_analytics_workspace_id != "" ? 1 : 0

  name                       = module.eventhub_naming.name
  target_resource_id         = module.eventhub.namespace_id
  log_analytics_workspace_id = var.log_analytics_workspace_id
}

# Outputs
output "eventhub" {
  value = {
    namespace_name = module.eventhub.namespace_name
    eventhub_name  = module.eventhub.eventhub_name
    namespace_id   = module.eventhub.namespace_id
  }
}
output "keyvault" { value = { name = module.keyvault.vault_name, uri = module.keyvault.vault_uri } }
output "resource_group" { value = azurerm_resource_group.main.name }
output "security_groups" { value = module.security_groups.group_names }
