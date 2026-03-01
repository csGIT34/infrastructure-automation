# terraform/modules/storage_account/main.tf
# Creates an Azure Storage Account with optional containers

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

resource "azurerm_storage_account" "main" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  account_tier                  = var.account_tier
  account_replication_type      = var.replication_type
  access_tier                   = var.access_tier
  min_tls_version               = "TLS1_2"
  https_traffic_only_enabled    = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled     = false
  tags                          = var.tags

  blob_properties {
    versioning_enabled = var.enable_versioning

    dynamic "delete_retention_policy" {
      for_each = var.soft_delete_days > 0 ? [1] : []
      content {
        days = var.soft_delete_days
      }
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "containers" {
  for_each = toset(var.containers)

  name               = each.value
  storage_account_id = azurerm_storage_account.main.id
}
