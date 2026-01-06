terraform {
    required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = "~> 3.0"
        }
    }
}

provider "azurerm" {
    features {}
}

resource "azurerm_resource_group" "tfstate" {
    name     = "rg-terraform-state"
    location = var.location

    tags = {
        Purpose   = "Terraform State Storage"
        ManagedBy = "Platform Team"
    }
}

resource "azurerm_storage_account" "tfstate" {
    name                            = "tfstate${random_string.suffix.result}"
    resource_group_name             = azurerm_resource_group.tfstate.name
    location                        = azurerm_resource_group.tfstate.location
    account_tier                    = "Standard"
    account_replication_type        = "GRS"

    enable_https_traffic_only = true
    min_tls_version           = "TLS1_2"

    blob_properties {
        versioning_enabled   = true
        change_feed_enabled  = true

        delete_retention_policy {
            days = 30
        }

        container_delete_retention_policy {
            days = 30
        }
    }

    network_rules {
        default_action = "Allow"
        bypass         = ["AzureServices"]
    }

    tags = azurerm_resource_group.tfstate.tags
}

resource "azurerm_storage_container" "tfstate" {
    name                  = "tfstate"
    storage_account_name  = azurerm_storage_account.tfstate.name
    container_access_type = "private"
}

resource "random_string" "suffix" {
    length  = 8
    special = false
    upper   = false
}

variable "location" {
    type    = string
    default = "eastus"
}

output "storage_account_name" {
    value = azurerm_storage_account.tfstate.name
}

output "container_name" {
    value = azurerm_storage_container.tfstate.name
}

output "resource_group_name" {
    value = azurerm_resource_group.tfstate.name
}
