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

resource "azurerm_resource_group" "monitoring" {
    name     = "rg-infrastructure-monitoring"
    location = var.location

    tags = {
        Purpose   = "Infrastructure Platform Monitoring"
        ManagedBy = "Terraform"
    }
}

resource "azurerm_log_analytics_workspace" "main" {
    name                = "law-infrastructure-platform"
    resource_group_name = azurerm_resource_group.monitoring.name
    location            = azurerm_resource_group.monitoring.location
    sku                 = "PerGB2018"
    retention_in_days   = 30

    tags = azurerm_resource_group.monitoring.tags
}

resource "azurerm_application_insights" "main" {
    name                = "appi-infrastructure-platform"
    resource_group_name = azurerm_resource_group.monitoring.name
    location            = azurerm_resource_group.monitoring.location
    workspace_id        = azurerm_log_analytics_workspace.main.id
    application_type    = "web"

    tags = azurerm_resource_group.monitoring.tags
}

resource "azurerm_storage_account" "metrics" {
    name                            = "stmetrics${random_string.suffix.result}"
    resource_group_name             = azurerm_resource_group.monitoring.name
    location                        = azurerm_resource_group.monitoring.location
    account_tier                    = "Standard"
    account_replication_type        = "LRS"

    tags = azurerm_resource_group.monitoring.tags
}

resource "azurerm_service_plan" "metrics" {
    name                = "asp-metrics-collector"
    resource_group_name = azurerm_resource_group.monitoring.name
    location            = azurerm_resource_group.monitoring.location
    os_type             = "Linux"
    sku_name            = "Y1"

    tags = azurerm_resource_group.monitoring.tags
}

resource "azurerm_linux_function_app" "metrics" {
    name                              = "func-metrics-${random_string.suffix.result}"
    resource_group_name               = azurerm_resource_group.monitoring.name
    location                          = azurerm_resource_group.monitoring.location
    service_plan_id                   = azurerm_service_plan.metrics.id
    storage_account_name              = azurerm_storage_account.metrics.name
    storage_account_access_key        = azurerm_storage_account.metrics.primary_access_key

    identity {
        type = "SystemAssigned"
    }

    site_config {
        application_stack {
            python_version = "3.11"
        }
    }

    app_settings = {
        "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key
        "FUNCTIONS_WORKER_RUNTIME"       = "python"
        "LOG_ANALYTICS_WORKSPACE_ID"     = azurerm_log_analytics_workspace.main.workspace_id
    }

    tags = azurerm_resource_group.monitoring.tags
}

resource "random_string" "suffix" {
    length  = 8
    special = false
    upper   = false
}

output "log_analytics_workspace_id" {
    value = azurerm_log_analytics_workspace.main.id
}

output "application_insights_key" {
    value     = azurerm_application_insights.main.instrumentation_key
    sensitive = true
}

output "metrics_function_url" {
    value = "https://${azurerm_linux_function_app.metrics.default_hostname}"
}
