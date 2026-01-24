# Test fixture: Key Vault with secrets
#
# Single consolidated test that validates:
# - Key Vault creation
# - RBAC configuration
# - Secret storage

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

# Create test resource group
resource "azurerm_resource_group" "test" {
  name     = "rg-tftest-keyvault-${var.resource_suffix}"
  location = var.location

  tags = {
    Purpose = "Terraform-Test"
    Module  = "keyvault"
  }
}

# Test the keyvault module with secrets
module "keyvault" {
  source = "../../../../modules/keyvault"

  name                = "kv-tftest-${var.resource_suffix}"
  resource_group_name = azurerm_resource_group.test.name
  location            = azurerm_resource_group.test.location

  config = {
    sku            = "standard"
    rbac_enabled   = true
    default_action = "Allow"
  }

  # Test secret storage
  secrets = {
    "db-connection-string" = "Server=test.database.windows.net;Database=testdb"
    "api-key"              = "test-api-key-12345"
  }

  tags = {
    Purpose = "Terraform-Test"
  }
}

# Outputs for assertions
output "vault_name" {
  value = module.keyvault.vault_name
}

output "vault_uri" {
  value = module.keyvault.vault_uri
}

output "vault_id" {
  value = module.keyvault.vault_id
}

output "secret_uris" {
  value = module.keyvault.secret_uris
}

output "resource_group_name" {
  value = azurerm_resource_group.test.name
}
