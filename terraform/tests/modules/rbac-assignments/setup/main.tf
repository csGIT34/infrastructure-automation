# Setup module for rbac-assignments tests
# Creates resource group and security group for testing RBAC

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

variable "location" {
  type    = string
  default = "eastus2"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

data "azuread_client_config" "current" {}

resource "azurerm_resource_group" "test" {
  name     = "rg-tftest-rbac-${random_string.suffix.result}"
  location = var.location

  tags = {
    Purpose = "Terraform-Test"
    Module  = "rbac-assignments"
  }
}

resource "azuread_group" "test" {
  display_name     = "sg-tftest-rbac-${random_string.suffix.result}"
  description      = "Test security group for RBAC testing"
  security_enabled = true
  owners           = [data.azuread_client_config.current.object_id]
}

output "suffix" {
  value = random_string.suffix.result
}

output "resource_group_id" {
  value = azurerm_resource_group.test.id
}

output "resource_group_name" {
  value = azurerm_resource_group.test.name
}

output "security_group_id" {
  value = azuread_group.test.object_id
}
