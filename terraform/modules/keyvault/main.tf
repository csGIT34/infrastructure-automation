terraform {
    required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = "~> 3.0"
        }
    }
}

variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "config" { type = any }
variable "tags" {
    type    = map(string)
    default = {}
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
    name                       = var.name
    resource_group_name        = var.resource_group_name
    location                   = var.location
    tenant_id                  = data.azurerm_client_config.current.tenant_id
    sku_name                   = lookup(var.config, "sku", "standard")
    soft_delete_retention_days = lookup(var.config, "soft_delete_days", 7)
    purge_protection_enabled   = lookup(var.config, "purge_protection", false)

    enable_rbac_authorization = lookup(var.config, "rbac_enabled", true)

    network_acls {
        default_action = lookup(var.config, "default_action", "Allow")
        bypass         = "AzureServices"
    }

    tags = var.tags
}

output "vault_uri" { value = azurerm_key_vault.main.vault_uri }
output "vault_id" { value = azurerm_key_vault.main.id }
output "vault_name" { value = azurerm_key_vault.main.name }
