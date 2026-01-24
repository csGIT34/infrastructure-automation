# Test fixture: Function App creation

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
  name     = "rg-tftest-func-${var.resource_suffix}"
  location = var.location

  tags = {
    Purpose = "Terraform-Test"
    Module  = "function-app"
  }
}

# Test the function-app module
module "function_app" {
  source = "../../../../modules/function-app"

  name                = "func-tftest-${var.resource_suffix}"
  resource_group_name = azurerm_resource_group.test.name
  location            = azurerm_resource_group.test.location

  config = {
    runtime         = "python"
    runtime_version = "3.11"
    sku             = "FC1"  # Flex Consumption
    os_type         = "Linux"
  }

  tags = {
    Purpose = "Terraform-Test"
  }
}

output "function_name" {
  value = module.function_app.name
}

output "function_id" {
  value = module.function_app.id
}

output "function_url" {
  value = module.function_app.url
}

output "principal_id" {
  value = module.function_app.principal_id
}

output "storage_account_name" {
  value = module.function_app.storage_account_name
}

output "resource_group_name" {
  value = azurerm_resource_group.test.name
}
