terraform {
    required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = ">= 4.0"
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

locals {
    containers = lookup(var.config, "containers", [])
}

resource "azurerm_storage_account" "main" {
    name                            = var.name
    resource_group_name             = var.resource_group_name
    location                        = var.location
    account_tier                    = lookup(var.config, "tier", "Standard")
    account_replication_type        = lookup(var.config, "replication", "LRS")

    https_traffic_only_enabled = true
    min_tls_version            = "TLS1_2"

    blob_properties {
        versioning_enabled = lookup(var.config, "versioning", false)

        dynamic "delete_retention_policy" {
            for_each = lookup(var.config, "soft_delete_days", null) != null ? [1] : []
            content {
                days = var.config.soft_delete_days
            }
        }
    }

    tags = var.tags
}

resource "azurerm_storage_container" "containers" {
    for_each = { for c in local.containers : c.name => c }

    name                  = each.value.name
    storage_account_name  = azurerm_storage_account.main.name
    container_access_type = lookup(each.value, "access_type", "private")
}

output "name" { value = azurerm_storage_account.main.name }
output "id" { value = azurerm_storage_account.main.id }
output "primary_blob_endpoint" { value = azurerm_storage_account.main.primary_blob_endpoint }
output "containers" { value = [for c in azurerm_storage_container.containers : c.name] }
