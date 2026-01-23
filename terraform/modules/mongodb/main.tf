terraform {
    required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = ">= 4.0"
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

resource "azurerm_cosmosdb_account" "main" {
    name                = var.name
    resource_group_name = var.resource_group_name
    location            = var.location
    offer_type          = "Standard"
    kind                = "MongoDB"

    capabilities {
        name = "EnableMongo"
    }

    capabilities {
        name = lookup(var.config, "serverless", false) ? "EnableServerless" : "DisableRateLimitingResponses"
    }

    consistency_policy {
        consistency_level = lookup(var.config, "consistency_level", "Session")
    }

    geo_location {
        location          = var.location
        failover_priority = 0
    }

    tags = var.tags
}

resource "azurerm_cosmosdb_mongo_database" "main" {
    name                = "${var.name}-db"
    resource_group_name = var.resource_group_name
    account_name        = azurerm_cosmosdb_account.main.name
    throughput          = lookup(var.config, "serverless", false) ? null : lookup(var.config, "throughput", 400)
}

output "connection_string" {
    value     = azurerm_cosmosdb_account.main.primary_mongodb_connection_string
    sensitive = true
}

output "endpoint" { value = azurerm_cosmosdb_account.main.endpoint }
output "database_name" { value = azurerm_cosmosdb_mongo_database.main.name }
output "account_id" { value = azurerm_cosmosdb_account.main.id }
