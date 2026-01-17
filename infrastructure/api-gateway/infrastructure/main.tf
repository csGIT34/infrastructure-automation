terraform {
    required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = "~> 3.0"
        }
        random = {
            source  = "hashicorp/random"
            version = "~> 3.0"
        }
    }
}

provider "azurerm" {
    features {}
}

variable "location" {
    type    = string
    default = "centralus"
}

resource "azurerm_resource_group" "api" {
    name     = "rg-infrastructure-api"
    location = var.location

    tags = {
        Purpose   = "Infrastructure API Gateway"
        ManagedBy = "Terraform"
    }
}

resource "azurerm_storage_account" "function" {
    name                            = "stfuncapi${random_string.suffix.result}"
    resource_group_name             = azurerm_resource_group.api.name
    location                        = azurerm_resource_group.api.location
    account_tier                    = "Standard"
    account_replication_type        = "LRS"

    tags = azurerm_resource_group.api.tags
}

resource "azurerm_service_plan" "function" {
    name                = "asp-infrastructure-api"
    resource_group_name = azurerm_resource_group.api.name
    location            = azurerm_resource_group.api.location
    os_type             = "Linux"
    sku_name            = "B1"  # Basic plan

    tags = azurerm_resource_group.api.tags
}

resource "azurerm_linux_function_app" "api" {
    name                              = "func-infra-api-${random_string.suffix.result}"
    resource_group_name               = azurerm_resource_group.api.name
    location                          = azurerm_resource_group.api.location
    service_plan_id                   = azurerm_service_plan.function.id
    storage_account_name              = azurerm_storage_account.function.name
    storage_account_access_key        = azurerm_storage_account.function.primary_access_key

    identity {
        type = "SystemAssigned"
    }

    site_config {
        application_stack {
            python_version = "3.11"
        }
    }

    tags = azurerm_resource_group.api.tags

    # App settings will be updated after Cosmos DB and Service Bus are created
    lifecycle {
        ignore_changes = [app_settings]
    }
}

resource "random_string" "suffix" {
    length  = 8
    special = false
    upper   = false
}

output "function_app_url" {
    value = "https://${azurerm_linux_function_app.api.default_hostname}"
}

output "function_app_name" {
    value = azurerm_linux_function_app.api.name
}

output "resource_group_name" {
    value = azurerm_resource_group.api.name
}

# Cosmos DB - Free tier (1000 RU/s + 25GB included)
resource "azurerm_cosmosdb_account" "api" {
    name                = "cosmos-infra-api-${random_string.suffix.result}"
    resource_group_name = azurerm_resource_group.api.name
    location            = azurerm_resource_group.api.location
    offer_type          = "Standard"
    kind                = "GlobalDocumentDB"

    # Enable free tier - only one per subscription
    free_tier_enabled = true

    consistency_policy {
        consistency_level = "Session"
    }

    geo_location {
        location          = azurerm_resource_group.api.location
        failover_priority = 0
    }

    tags = azurerm_resource_group.api.tags
}

resource "azurerm_cosmosdb_sql_database" "api" {
    name                = "infrastructure-db"
    resource_group_name = azurerm_cosmosdb_account.api.resource_group_name
    account_name        = azurerm_cosmosdb_account.api.name
}

resource "azurerm_cosmosdb_sql_container" "requests" {
    name                = "requests"
    resource_group_name = azurerm_cosmosdb_account.api.resource_group_name
    account_name        = azurerm_cosmosdb_account.api.name
    database_name       = azurerm_cosmosdb_sql_database.api.name
    partition_key_paths = ["/requestId"]

    # Use autoscale for free tier
    autoscale_settings {
        max_throughput = 1000
    }
}

# Service Bus - Basic tier (lowest cost)
resource "azurerm_servicebus_namespace" "api" {
    name                = "sb-infra-api-${random_string.suffix.result}"
    resource_group_name = azurerm_resource_group.api.name
    location            = azurerm_resource_group.api.location
    sku                 = "Basic"

    tags = azurerm_resource_group.api.tags
}

# Environment-specific queues (API sends to infrastructure-requests-{env})
resource "azurerm_servicebus_queue" "requests_dev" {
    name         = "infrastructure-requests-dev"
    namespace_id = azurerm_servicebus_namespace.api.id

    max_delivery_count = 3
    lock_duration      = "PT5M"
}

resource "azurerm_servicebus_queue" "requests_staging" {
    name         = "infrastructure-requests-staging"
    namespace_id = azurerm_servicebus_namespace.api.id

    max_delivery_count = 3
    lock_duration      = "PT5M"
}

resource "azurerm_servicebus_queue" "requests_prod" {
    name         = "infrastructure-requests-prod"
    namespace_id = azurerm_servicebus_namespace.api.id

    max_delivery_count = 3
    lock_duration      = "PT5M"
}

output "cosmos_db_endpoint" {
    value = azurerm_cosmosdb_account.api.endpoint
}

output "service_bus_namespace" {
    value = azurerm_servicebus_namespace.api.name
}
