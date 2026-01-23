terraform {
    required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = "~> 3.0"
        }
        azapi = {
            source  = "azure/azapi"
            version = "~> 1.0"
        }
        random = {
            source  = "hashicorp/random"
            version = "~> 3.0"
        }
    }
}

resource "random_string" "storage_suffix" {
    length  = 8
    special = false
    upper   = false
}

locals {
    runtime  = lookup(var.config, "runtime", "python")
    sku_name = lookup(var.config, "sku", "Y1")
    os_type  = lookup(var.config, "os_type", "Linux")
    app_settings = lookup(var.config, "app_settings", {})

    # Use consumption plan for Y1 (created via azapi to avoid quota issues)
    use_consumption = local.sku_name == "Y1"

    # Default versions per runtime
    default_versions = {
        python     = "3.11"
        node       = "20"
        dotnet     = "8.0"
        java       = "17"
        powershell = "7.4"
    }

    # Use provided version or runtime-appropriate default (empty string = use default)
    provided_version = lookup(var.config, "runtime_version", "")
    runtime_version  = local.provided_version != "" ? local.provided_version : local.default_versions[local.runtime]

    # Version strings per runtime - only the matching runtime gets a value
    python_version     = local.runtime == "python" ? local.runtime_version : null
    node_version       = local.runtime == "node" ? local.runtime_version : null
    dotnet_version     = local.runtime == "dotnet" ? local.runtime_version : null
    java_version       = local.runtime == "java" ? local.runtime_version : null
    powershell_version = local.runtime == "powershell" ? local.runtime_version : null

    # Linux FX version string for azapi
    linux_fx_version = local.runtime == "python" ? "PYTHON|${local.runtime_version}" : (
        local.runtime == "node" ? "NODE|${local.runtime_version}" : (
        local.runtime == "dotnet" ? "DOTNET|${local.runtime_version}" : (
        local.runtime == "java" ? "JAVA|${local.runtime_version}" : ""
    )))
}

# Storage account for function app
resource "azurerm_storage_account" "func" {
    name                     = "stfunc${random_string.storage_suffix.result}"
    resource_group_name      = var.resource_group_name
    location                 = var.location
    account_tier             = "Standard"
    account_replication_type = "LRS"
    min_tls_version          = "TLS1_2"

    tags = var.tags
}

# ---------------------------------------------------------
# Dedicated App Service Plan (for non-consumption SKUs)
# ---------------------------------------------------------
resource "azurerm_service_plan" "main" {
    count = local.use_consumption ? 0 : 1

    name                = "asp-${var.name}"
    resource_group_name = var.resource_group_name
    location            = var.location
    os_type             = local.os_type
    sku_name            = local.sku_name

    tags = var.tags
}

# ---------------------------------------------------------
# Non-Consumption Function Apps (using azurerm provider)
# ---------------------------------------------------------
resource "azurerm_linux_function_app" "main" {
    count = !local.use_consumption && local.os_type == "Linux" ? 1 : 0

    name                = var.name
    resource_group_name = var.resource_group_name
    location            = var.location

    storage_account_name       = azurerm_storage_account.func.name
    storage_account_access_key = azurerm_storage_account.func.primary_access_key
    service_plan_id            = azurerm_service_plan.main[0].id

    site_config {
        application_stack {
            python_version = local.python_version
            node_version   = local.node_version
            dotnet_version = local.dotnet_version
            java_version   = local.java_version
        }

        cors {
            allowed_origins = lookup(var.config, "cors_origins", ["*"])
        }
    }

    app_settings = merge({
        "FUNCTIONS_WORKER_RUNTIME" = local.runtime
    }, local.app_settings)

    identity {
        type = "SystemAssigned"
    }

    tags = var.tags
}

resource "azurerm_windows_function_app" "main" {
    count = !local.use_consumption && local.os_type == "Windows" ? 1 : 0

    name                = var.name
    resource_group_name = var.resource_group_name
    location            = var.location

    storage_account_name       = azurerm_storage_account.func.name
    storage_account_access_key = azurerm_storage_account.func.primary_access_key
    service_plan_id            = azurerm_service_plan.main[0].id

    site_config {
        application_stack {
            powershell_core_version = local.powershell_version
            node_version            = local.node_version
            dotnet_version          = local.dotnet_version
            java_version            = local.java_version
        }
    }

    app_settings = merge({
        "FUNCTIONS_WORKER_RUNTIME" = local.runtime
    }, local.app_settings)

    identity {
        type = "SystemAssigned"
    }

    tags = var.tags
}

# ---------------------------------------------------------
# Consumption Function App (using azapi to avoid quota issues)
# Creates function app with shared regional consumption plan
# ---------------------------------------------------------
resource "azapi_resource" "consumption_function_app" {
    count = local.use_consumption && local.os_type == "Linux" ? 1 : 0

    type      = "Microsoft.Web/sites@2023-01-01"
    name      = var.name
    location  = var.location
    parent_id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/${var.resource_group_name}"

    identity {
        type = "SystemAssigned"
    }

    body = jsonencode({
        kind = "functionapp,linux"
        properties = {
            reserved = true
            siteConfig = {
                linuxFxVersion = local.linux_fx_version
                appSettings = concat([
                    {
                        name  = "FUNCTIONS_WORKER_RUNTIME"
                        value = local.runtime
                    },
                    {
                        name  = "FUNCTIONS_EXTENSION_VERSION"
                        value = "~4"
                    },
                    {
                        name  = "AzureWebJobsStorage"
                        value = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.func.name};AccountKey=${azurerm_storage_account.func.primary_access_key};EndpointSuffix=core.windows.net"
                    },
                    {
                        name  = "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING"
                        value = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.func.name};AccountKey=${azurerm_storage_account.func.primary_access_key};EndpointSuffix=core.windows.net"
                    },
                    {
                        name  = "WEBSITE_CONTENTSHARE"
                        value = lower(var.name)
                    }
                ], [for k, v in local.app_settings : { name = k, value = v }])
            }
        }
    })

    tags = var.tags

    response_export_values = ["properties.defaultHostName", "identity.principalId"]
}

data "azurerm_subscription" "current" {}
