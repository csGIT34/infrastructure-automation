# Test fixture: PostgreSQL Flexible Server creation

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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

# Create test resource group
resource "azurerm_resource_group" "test" {
  name     = "rg-tftest-psql-${var.resource_suffix}"
  location = var.location

  tags = {
    Purpose = "Terraform-Test"
    Module  = "postgresql"
  }
}

# Test the postgresql module
module "postgresql" {
  source = "../../../../modules/postgresql"

  name                = "psql-tftest-${var.resource_suffix}"
  resource_group_name = azurerm_resource_group.test.name
  location            = azurerm_resource_group.test.location

  config = {
    version               = "14"
    sku                   = "B_Standard_B1ms"
    storage_mb            = 32768
    backup_retention_days = 7
    geo_redundant_backup  = false
  }

  tags = {
    Purpose = "Terraform-Test"
  }
}

output "server_fqdn" {
  value = module.postgresql.server_fqdn
}

output "server_id" {
  value = module.postgresql.server_id
}

output "database_name" {
  value = module.postgresql.database_name
}

output "resource_group_name" {
  value = azurerm_resource_group.test.name
}
