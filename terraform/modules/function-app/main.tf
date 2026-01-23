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
        dynamic "application_stack" {
            for_each = local.runtime == "python" ? [1] : []
            content {
                python_version = local.runtime_version
            }
        }
        dynamic "application_stack" {
            for_each = local.runtime == "node" ? [1] : []
            content {
                node_version = local.runtime_version
            }
        }
        dynamic "application_stack" {
            for_each = local.runtime == "dotnet" ? [1] : []
            content {
                dotnet_version = local.runtime_version
            }
        }
        dynamic "application_stack" {
            for_each = local.runtime == "java" ? [1] : []
            content {
                java_version = local.runtime_version
            }
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
        dynamic "application_stack" {
            for_each = local.runtime == "powershell" ? [1] : []
            content {
                powershell_core_version = local.runtime_version
            }
        }
        dynamic "application_stack" {
            for_each = local.runtime == "node" ? [1] : []
            content {
                node_version = local.runtime_version
            }
        }
        dynamic "application_stack" {
            for_each = local.runtime == "dotnet" ? [1] : []
            content {
                dotnet_version = local.runtime_version
            }
        }
        dynamic "application_stack" {
            for_each = local.runtime == "java" ? [1] : []
            content {
                java_version = local.runtime_version
            }
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
