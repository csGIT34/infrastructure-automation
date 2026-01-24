# Test fixture: Diagnostic Settings
#
# Creates a Key Vault as target resource and Log Analytics workspace,
# then configures diagnostic settings to validate the module.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
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
  type        = string
  description = "Email of the test owner"
  default     = "test@example.com"
}

# Create test resource group
resource "azurerm_resource_group" "test" {
  name     = "rg-tftest-diag-${var.resource_suffix}"
  location = var.location

  tags = {
    Purpose    = "Terraform-Test"
    Module     = "diagnostic-settings"
    OwnerEmail = var.owner_email
  }
}

# Create Log Analytics workspace as the log destination
resource "azurerm_log_analytics_workspace" "test" {
  name                = "law-tftest-${var.resource_suffix}"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    Purpose = "Terraform-Test"
    Module  = "diagnostic-settings"
  }
}

# Create a Key Vault as the target resource for diagnostic settings
resource "azurerm_key_vault" "test" {
  name                       = "kv-tftest-${var.resource_suffix}"
  location                   = azurerm_resource_group.test.location
  resource_group_name        = azurerm_resource_group.test.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  rbac_authorization_enabled = true

  tags = {
    Purpose = "Terraform-Test"
    Module  = "diagnostic-settings"
  }
}

data "azurerm_client_config" "current" {}

# Test the diagnostic-settings module
module "diagnostic_settings" {
  source = "../../../../modules/diagnostic-settings"

  name                       = "tftest-${var.resource_suffix}"
  target_resource_id         = azurerm_key_vault.test.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.test.id

  logs = [
    "AuditEvent",
    "AzurePolicyEvaluationDetails"
  ]

  metrics = [
    "AllMetrics"
  ]

  retention_days = 30
}

# Outputs for assertions
output "diagnostic_setting_id" {
  value = module.diagnostic_settings.id
}

output "diagnostic_setting_name" {
  value = module.diagnostic_settings.name
}

output "target_resource_id" {
  value = azurerm_key_vault.test.id
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.test.id
}

output "resource_group_name" {
  value = azurerm_resource_group.test.name
}
