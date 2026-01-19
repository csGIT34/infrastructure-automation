terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "config" { type = any }
variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  sku               = lookup(var.config, "sku", "Basic")
  capacity          = lookup(var.config, "capacity", 1)
  partition_count   = lookup(var.config, "partition_count", 2)
  message_retention = lookup(var.config, "message_retention", 1)
  auto_inflate      = lookup(var.config, "auto_inflate_enabled", false)
  max_throughput    = lookup(var.config, "max_throughput_units", null)

  # Event hubs to create
  hubs = lookup(var.config, "hubs", [{ name = "default" }])

  # Consumer groups per hub
  consumer_groups = lookup(var.config, "consumer_groups", [])

  # Authorization rules
  auth_rules = lookup(var.config, "authorization_rules", [])
}

resource "azurerm_eventhub_namespace" "main" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = local.sku
  capacity            = local.capacity

  auto_inflate_enabled     = local.auto_inflate
  maximum_throughput_units = local.auto_inflate ? local.max_throughput : null

  tags = var.tags
}

resource "azurerm_eventhub" "hubs" {
  for_each = { for h in local.hubs : h.name => h }

  name                = each.value.name
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = var.resource_group_name
  partition_count     = lookup(each.value, "partition_count", local.partition_count)
  message_retention   = lookup(each.value, "message_retention", local.message_retention)
}

resource "azurerm_eventhub_consumer_group" "groups" {
  for_each = { for cg in local.consumer_groups : "${cg.hub_name}-${cg.name}" => cg }

  name                = each.value.name
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = each.value.hub_name
  resource_group_name = var.resource_group_name
  user_metadata       = lookup(each.value, "user_metadata", null)

  depends_on = [azurerm_eventhub.hubs]
}

resource "azurerm_eventhub_namespace_authorization_rule" "rules" {
  for_each = { for r in local.auth_rules : r.name => r }

  name                = each.value.name
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = var.resource_group_name

  listen = lookup(each.value, "listen", false)
  send   = lookup(each.value, "send", false)
  manage = lookup(each.value, "manage", false)
}

output "namespace_name" {
  value = azurerm_eventhub_namespace.main.name
}

output "namespace_id" {
  value = azurerm_eventhub_namespace.main.id
}

output "default_connection_string" {
  value     = azurerm_eventhub_namespace.main.default_primary_connection_string
  sensitive = true
}

output "hubs" {
  value = [for h in azurerm_eventhub.hubs : {
    name            = h.name
    partition_count = h.partition_count
    partition_ids   = h.partition_ids
  }]
}
