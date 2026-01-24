# Test fixture: Azure SQL Server with database
#
# Single consolidated test that validates:
# - SQL Server creation
# - Database creation
# - Firewall rules
# - Connection string generation

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
  description = "Owner email for tagging"
  default     = "terraform-test@example.com"
}

# Create test resource group
resource "azurerm_resource_group" "test" {
  name     = "rg-tftest-azure-sql-${var.resource_suffix}"
  location = var.location

  tags = {
    Purpose = "Terraform-Test"
    Module  = "azure-sql"
    Owner   = var.owner_email
  }
}

# Test the azure-sql module
module "azure_sql" {
  source = "../../../../modules/azure-sql"

  name                = "sql-tftest-${var.resource_suffix}"
  resource_group_name = azurerm_resource_group.test.name
  location            = azurerm_resource_group.test.location

  config = {
    sku         = "Basic"
    max_size_gb = 2
    databases = [
      {
        name = "testdb"
        sku  = "Basic"
      }
    ]
    firewall_rules = [
      {
        name             = "AllowAzureServices"
        start_ip_address = "0.0.0.0"
        end_ip_address   = "0.0.0.0"
      }
    ]
  }

  tags = {
    Purpose = "Terraform-Test"
    Owner   = var.owner_email
  }
}

# Outputs for assertions
output "server_id" {
  value = module.azure_sql.server_id
}

output "server_name" {
  value = module.azure_sql.server_name
}

output "server_fqdn" {
  value = module.azure_sql.server_fqdn
}

output "databases" {
  value = module.azure_sql.databases
}

output "database_name" {
  value = module.azure_sql.database_name
}

output "admin_login" {
  value = module.azure_sql.admin_login
}

output "connection_string_template" {
  value = module.azure_sql.connection_string_template
}

output "resource_group_name" {
  value = azurerm_resource_group.test.name
}
