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
    default = "eastus"
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
    sku_name            = "Y1"  # Consumption plan - FREE tier (1M executions/month)

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

        cors {
            allowed_origins = ["https://portal.yourcompany.com"]
        }
    }

    app_settings = {
        "SERVICEBUS_NAMESPACE"            = azurerm_servicebus_namespace.main.name
        "COSMOS_ENDPOINT"                 = azurerm_cosmosdb_account.main.endpoint
        "COSMOS_DATABASE"                 = azurerm_cosmosdb_sql_database.main.name
        "APPINSIGHTS_INSTRUMENTATIONKEY"  = azurerm_application_insights.api.instrumentation_key
        "FUNCTIONS_WORKER_RUNTIME"        = "python"
    }

    tags = azurerm_resource_group.api.tags
}

resource "azurerm_application_insights" "api" {
    name                = "appi-infrastructure-api"
    resource_group_name = azurerm_resource_group.api.name
    location            = azurerm_resource_group.api.location
    application_type    = "web"

    tags = azurerm_resource_group.api.tags
}

resource "azurerm_servicebus_namespace" "main" {
    name                = "sb-infra-requests-${random_string.suffix.result}"
    resource_group_name = azurerm_resource_group.api.name
    location            = azurerm_resource_group.api.location
    sku                 = "Basic"  # Basic tier - ~$0.05 per million operations

    tags = azurerm_resource_group.api.tags
}

resource "azurerm_servicebus_queue" "prod" {
    name         = "infrastructure-requests-prod"
    namespace_id = azurerm_servicebus_namespace.main.id

    max_size_in_megabytes = 1024  # Basic tier max
    max_delivery_count    = 3
    # Note: Basic tier doesn't support duplicate detection or custom lock duration
}

resource "azurerm_servicebus_queue" "staging" {
    name         = "infrastructure-requests-staging"
    namespace_id = azurerm_servicebus_namespace.main.id

    max_size_in_megabytes = 1024
    max_delivery_count    = 5
}

resource "azurerm_servicebus_queue" "dev" {
    name         = "infrastructure-requests-dev"
    namespace_id = azurerm_servicebus_namespace.main.id

    max_size_in_megabytes = 1024
    max_delivery_count    = 10
}

resource "azurerm_cosmosdb_account" "main" {
    name                       = "cosmos-infra-${random_string.suffix.result}"
    resource_group_name        = azurerm_resource_group.api.name
    location                   = azurerm_resource_group.api.location
    offer_type                 = "Standard"
    kind                       = "GlobalDocumentDB"
    enable_free_tier           = true  # FREE TIER: 1000 RU/s + 25GB storage

    consistency_policy {
        consistency_level = "Session"
    }

    geo_location {
        location          = azurerm_resource_group.api.location
        failover_priority = 0
    }

    # Use periodic backup (free) instead of continuous (paid)
    backup {
        type                = "Periodic"
        interval_in_minutes = 240
        retention_in_hours  = 8
        storage_redundancy  = "Local"
    }

    tags = azurerm_resource_group.api.tags
}

resource "azurerm_cosmosdb_sql_database" "main" {
    name                = "infrastructure"
    resource_group_name = azurerm_resource_group.api.name
    account_name        = azurerm_cosmosdb_account.main.name
}

resource "azurerm_cosmosdb_sql_container" "requests" {
    name                = "infrastructure-requests"
    resource_group_name = azurerm_resource_group.api.name
    account_name        = azurerm_cosmosdb_account.main.name
    database_name       = azurerm_cosmosdb_sql_database.main.name
    partition_key_path  = "/id"
    # No throughput specified - uses shared database throughput from free tier
}

resource "azurerm_role_assignment" "function_servicebus" {
    scope                = azurerm_servicebus_namespace.main.id
    role_definition_name = "Azure Service Bus Data Owner"
    principal_id         = azurerm_linux_function_app.api.identity[0].principal_id
}

resource "azurerm_cosmosdb_sql_role_assignment" "function_cosmos_data" {
    resource_group_name = azurerm_resource_group.api.name
    account_name        = azurerm_cosmosdb_account.main.name
    role_definition_id  = "${azurerm_cosmosdb_account.main.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
    principal_id        = azurerm_linux_function_app.api.identity[0].principal_id
    scope               = azurerm_cosmosdb_account.main.id
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

output "function_app_id" {
    value = azurerm_linux_function_app.api.id
}

output "servicebus_namespace" {
    value = azurerm_servicebus_namespace.main.name
}

output "servicebus_namespace_id" {
    value = azurerm_servicebus_namespace.main.id
}

output "cosmos_endpoint" {
    value = azurerm_cosmosdb_account.main.endpoint
}

output "cosmosdb_account_id" {
    value = azurerm_cosmosdb_account.main.id
}

output "resource_group_name" {
    value = azurerm_resource_group.api.name
}
