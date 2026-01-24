# Test fixture: MongoDB (Cosmos DB with MongoDB API)
#
# Single consolidated test that validates:
# - Cosmos DB account creation with MongoDB API
# - Database creation
# - Connection string output

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
  type    = string
  default = "test@example.com"
}

# Create test resource group
resource "azurerm_resource_group" "test" {
  name     = "rg-tftest-mongodb-${var.resource_suffix}"
  location = var.location

  tags = {
    Purpose = "Terraform-Test"
    Module  = "mongodb"
    Owner   = var.owner_email
  }
}

# Test the mongodb module
module "mongodb" {
  source = "../../../../modules/mongodb"

  name                = "cosmos-tftest-${var.resource_suffix}"
  resource_group_name = azurerm_resource_group.test.name
  location            = azurerm_resource_group.test.location

  config = {
    serverless        = false
    consistency_level = "Session"
    throughput        = 400
  }

  tags = {
    Purpose = "Terraform-Test"
    Owner   = var.owner_email
  }
}

# Outputs for assertions
output "account_id" {
  value = module.mongodb.account_id
}

output "endpoint" {
  value = module.mongodb.endpoint
}

output "database_name" {
  value = module.mongodb.database_name
}

output "connection_string" {
  value     = module.mongodb.connection_string
  sensitive = true
}

output "resource_group_name" {
  value = azurerm_resource_group.test.name
}
