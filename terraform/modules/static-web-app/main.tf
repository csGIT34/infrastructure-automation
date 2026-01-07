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
    sku_tier = lookup(var.config, "sku_tier", "Free")
    sku_size = lookup(var.config, "sku_size", "Free")
}

resource "azurerm_static_web_app" "main" {
    name                = var.name
    resource_group_name = var.resource_group_name
    location            = var.location

    sku_tier = local.sku_tier
    sku_size = local.sku_size

    tags = var.tags
}

output "name" {
    value = azurerm_static_web_app.main.name
}

output "id" {
    value = azurerm_static_web_app.main.id
}

output "default_host_name" {
    value = azurerm_static_web_app.main.default_host_name
}

output "api_key" {
    value     = azurerm_static_web_app.main.api_key
    sensitive = true
}
