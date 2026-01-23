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

resource "random_string" "storage_suffix" {
    length  = 8
    special = false
    upper   = false
}

locals {
    runtime         = lookup(var.config, "runtime", "python")
    runtime_version = lookup(var.config, "runtime_version", "3.11")
    sku_name        = lookup(var.config, "sku", "Y1")
    os_type         = lookup(var.config, "os_type", "Linux")
    app_settings    = lookup(var.config, "app_settings", {})

    # Application stack configuration - only one should be set
    linux_app_stack = {
        python = local.runtime == "python" ? { python_version = local.runtime_version } : null
        node   = local.runtime == "node" ? { node_version = local.runtime_version } : null
        dotnet = local.runtime == "dotnet" ? { dotnet_version = local.runtime_version } : null
        java   = local.runtime == "java" ? { java_version = local.runtime_version } : null
    }

    # Get the non-null stack config
    active_linux_stack = coalesce(
        local.linux_app_stack.python,
        local.linux_app_stack.node,
        local.linux_app_stack.dotnet,
        local.linux_app_stack.java,
        { python_version = "3.11" }  # fallback
    )
}

resource "azurerm_storage_account" "func" {
    name                     = "stfunc${random_string.storage_suffix.result}"
    resource_group_name      = var.resource_group_name
    location                 = var.location
    account_tier             = "Standard"
    account_replication_type = "LRS"
    min_tls_version          = "TLS1_2"

    tags = var.tags
}

resource "azurerm_service_plan" "main" {
    name                = "asp-${var.name}"
    resource_group_name = var.resource_group_name
    location            = var.location
    os_type             = local.os_type
    sku_name            = local.sku_name

    tags = var.tags
}

resource "azurerm_linux_function_app" "main" {
    count = local.os_type == "Linux" ? 1 : 0

    name                = var.name
    resource_group_name = var.resource_group_name
    location            = var.location

    storage_account_name       = azurerm_storage_account.func.name
    storage_account_access_key = azurerm_storage_account.func.primary_access_key
    service_plan_id            = azurerm_service_plan.main.id

    site_config {
        application_stack {
            python_version = lookup(local.active_linux_stack, "python_version", null)
            node_version   = lookup(local.active_linux_stack, "node_version", null)
            dotnet_version = lookup(local.active_linux_stack, "dotnet_version", null)
            java_version   = lookup(local.active_linux_stack, "java_version", null)
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
    count = local.os_type == "Windows" ? 1 : 0

    name                = var.name
    resource_group_name = var.resource_group_name
    location            = var.location

    storage_account_name       = azurerm_storage_account.func.name
    storage_account_access_key = azurerm_storage_account.func.primary_access_key
    service_plan_id            = azurerm_service_plan.main.id

    site_config {
        application_stack {
            powershell_core_version = local.runtime == "powershell" ? local.runtime_version : null
            node_version            = local.runtime == "node" ? local.runtime_version : null
            dotnet_version          = local.runtime == "dotnet" ? local.runtime_version : null
            java_version            = local.runtime == "java" ? local.runtime_version : null
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
