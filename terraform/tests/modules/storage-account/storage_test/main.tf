# Test fixture: Storage account with containers

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

resource "azurerm_resource_group" "test" {
  name     = "rg-tftest-storage-${var.resource_suffix}"
  location = var.location

  tags = {
    Purpose = "Terraform-Test"
    Module  = "storage-account"
  }
}

module "storage" {
  source = "../../../../modules/storage-account"

  name                = "sttftest${var.resource_suffix}"
  resource_group_name = azurerm_resource_group.test.name
  location            = azurerm_resource_group.test.location

  config = {
    tier             = "Standard"
    replication      = "LRS"
    versioning       = true
    soft_delete_days = 7
    containers = [
      { name = "data", access_type = "private" },
      { name = "logs", access_type = "private" },
      { name = "backups", access_type = "private" }
    ]
  }

  tags = {
    Purpose = "Terraform-Test"
  }
}

output "storage_name" {
  value = module.storage.name
}

output "storage_id" {
  value = module.storage.id
}

output "primary_blob_endpoint" {
  value = module.storage.primary_blob_endpoint
}

output "containers" {
  value = module.storage.containers
}

output "resource_group_name" {
  value = azurerm_resource_group.test.name
}
