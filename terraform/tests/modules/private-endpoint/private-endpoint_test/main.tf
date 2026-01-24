# Test fixture: Private Endpoint with Key Vault target
#
# Creates minimal infrastructure to test the private-endpoint module:
# - Resource Group
# - Virtual Network with subnet
# - Key Vault (as target resource)
# - Private Endpoint connecting to Key Vault

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

# Get current client config for Key Vault tenant
data "azurerm_client_config" "current" {}

# Create test resource group
resource "azurerm_resource_group" "test" {
  name     = "rg-tftest-pe-${var.resource_suffix}"
  location = var.location

  tags = {
    Purpose     = "Terraform-Test"
    Module      = "private-endpoint"
    Owner       = var.owner_email
  }
}

# Create virtual network for private endpoint
resource "azurerm_virtual_network" "test" {
  name                = "vnet-tftest-pe-${var.resource_suffix}"
  location            = azurerm_resource_group.test.location
  resource_group_name = azurerm_resource_group.test.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    Purpose = "Terraform-Test"
    Module  = "private-endpoint"
  }
}

# Create subnet for private endpoint
resource "azurerm_subnet" "endpoint" {
  name                 = "snet-endpoint"
  resource_group_name  = azurerm_resource_group.test.name
  virtual_network_name = azurerm_virtual_network.test.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create Key Vault as target resource for private endpoint
resource "azurerm_key_vault" "test" {
  name                       = "kv-tftest-pe-${var.resource_suffix}"
  location                   = azurerm_resource_group.test.location
  resource_group_name        = azurerm_resource_group.test.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  # Allow Azure services to access for private endpoint setup
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = {
    Purpose = "Terraform-Test"
    Module  = "private-endpoint"
  }
}

# Test the private-endpoint module
module "private_endpoint" {
  source = "../../../../modules/private-endpoint"

  name                = "tftest-kv-${var.resource_suffix}"
  resource_group_name = azurerm_resource_group.test.name
  location            = azurerm_resource_group.test.location
  subnet_id           = azurerm_subnet.endpoint.id
  target_resource_id  = azurerm_key_vault.test.id
  subresource_names   = ["vault"]

  tags = {
    Purpose = "Terraform-Test"
    Module  = "private-endpoint"
  }
}

# Outputs for assertions
output "endpoint_id" {
  value = module.private_endpoint.id
}

output "endpoint_private_ip" {
  value = module.private_endpoint.private_ip
}

output "endpoint_network_interface_id" {
  value = module.private_endpoint.network_interface_id
}

output "endpoint_custom_dns_configs" {
  value = module.private_endpoint.custom_dns_configs
}

output "resource_group_name" {
  value = azurerm_resource_group.test.name
}

output "keyvault_id" {
  value = azurerm_key_vault.test.id
}

output "subnet_id" {
  value = azurerm_subnet.endpoint.id
}
