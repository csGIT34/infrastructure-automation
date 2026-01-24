# Test fixture: Network Rules for Storage Account
#
# Creates a storage account and applies network rules to validate:
# - Network rules are applied correctly
# - Default deny action works
# - IP allow list works
# - Azure services bypass works

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
  description = "Owner email for resource tagging"
  default     = "test@example.com"
}

# Create test resource group
resource "azurerm_resource_group" "test" {
  name     = "rg-tftest-netrules-${var.resource_suffix}"
  location = var.location

  tags = {
    Purpose = "Terraform-Test"
    Module  = "network-rules"
    Owner   = var.owner_email
  }
}

# Create a storage account to apply network rules to
resource "azurerm_storage_account" "test" {
  name                     = "sttftest${var.resource_suffix}"
  resource_group_name      = azurerm_resource_group.test.name
  location                 = azurerm_resource_group.test.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    Purpose = "Terraform-Test"
    Module  = "network-rules"
    Owner   = var.owner_email
  }
}

# Test the network-rules module with storage account
module "network_rules" {
  source = "../../../../modules/network-rules"

  resource_type         = "storage"
  resource_id           = azurerm_storage_account.test.id
  default_action        = "Deny"
  allowed_ips           = ["203.0.113.0/24", "198.51.100.1"]
  bypass_azure_services = true
}

# Outputs for assertions
output "configured" {
  value = module.network_rules.configured
}

output "default_action" {
  value = module.network_rules.default_action
}

output "allowed_ips_count" {
  value = module.network_rules.allowed_ips_count
}

output "allowed_subnets_count" {
  value = module.network_rules.allowed_subnets_count
}

output "storage_account_name" {
  value = azurerm_storage_account.test.name
}

output "storage_account_id" {
  value = azurerm_storage_account.test.id
}

output "resource_group_name" {
  value = azurerm_resource_group.test.name
}
