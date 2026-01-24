# Test fixture: Static Web App
#
# Single consolidated test that validates:
# - Static Web App creation
# - SKU configuration
# - Output values

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
  default = "test-owner@example.com"
}

# Create test resource group
resource "azurerm_resource_group" "test" {
  name     = "rg-tftest-staticwebapp-${var.resource_suffix}"
  location = var.location

  tags = {
    Purpose = "Terraform-Test"
    Module  = "static-web-app"
    Owner   = var.owner_email
  }
}

# Test the static-web-app module
module "static_web_app" {
  source = "../../../../modules/static-web-app"

  name                = "stapp-tftest-${var.resource_suffix}"
  resource_group_name = azurerm_resource_group.test.name
  location            = azurerm_resource_group.test.location

  config = {
    sku_tier = "Free"
    sku_size = "Free"
  }

  tags = {
    Purpose = "Terraform-Test"
    Owner   = var.owner_email
  }
}

# Outputs for assertions
output "static_web_app_name" {
  value = module.static_web_app.name
}

output "static_web_app_id" {
  value = module.static_web_app.id
}

output "default_host_name" {
  value = module.static_web_app.default_host_name
}

output "api_key" {
  value     = module.static_web_app.api_key
  sensitive = true
}

output "resource_group_name" {
  value = azurerm_resource_group.test.name
}
