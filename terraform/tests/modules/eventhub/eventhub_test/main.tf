# Test fixture: Event Hub namespace with hubs and consumer groups
#
# Single consolidated test that validates:
# - Event Hub namespace creation
# - Event Hub creation
# - Consumer group configuration
# - Authorization rules

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
  name     = "rg-tftest-eventhub-${var.resource_suffix}"
  location = var.location

  tags = {
    Purpose = "Terraform-Test"
    Module  = "eventhub"
    Owner   = var.owner_email
  }
}

# Test the eventhub module with hubs and consumer groups
module "eventhub" {
  source = "../../../../modules/eventhub"

  name                = "evhns-tftest-${var.resource_suffix}"
  resource_group_name = azurerm_resource_group.test.name
  location            = azurerm_resource_group.test.location

  config = {
    sku               = "Basic"
    capacity          = 1
    partition_count   = 2
    message_retention = 1

    hubs = [
      { name = "events" },
      { name = "telemetry", partition_count = 4 }
    ]

    consumer_groups = [
      { hub_name = "events", name = "processor" },
      { hub_name = "telemetry", name = "analytics", user_metadata = "Analytics consumer" }
    ]

    authorization_rules = [
      { name = "sender", send = true },
      { name = "listener", listen = true }
    ]
  }

  tags = {
    Purpose = "Terraform-Test"
    Owner   = var.owner_email
  }
}

# Outputs for assertions
output "namespace_name" {
  value = module.eventhub.namespace_name
}

output "namespace_id" {
  value = module.eventhub.namespace_id
}

output "hubs" {
  value = module.eventhub.hubs
}

output "resource_group_name" {
  value = azurerm_resource_group.test.name
}
