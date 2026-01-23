locals {
    # Determine which resource type was created
    is_flex = local.use_flex_consumption
    is_linux = local.os_type == "Linux"

    # Get values from the appropriate resource
    func_id = local.is_flex ? (
        local.is_linux ? azurerm_function_app_flex_consumption.main[0].id : null
    ) : (
        local.is_linux ? azurerm_linux_function_app.main[0].id : azurerm_windows_function_app.main[0].id
    )

    func_hostname = local.is_flex ? (
        local.is_linux ? azurerm_function_app_flex_consumption.main[0].default_hostname : null
    ) : (
        local.is_linux ? azurerm_linux_function_app.main[0].default_hostname : azurerm_windows_function_app.main[0].default_hostname
    )

    func_principal_id = local.is_flex ? (
        local.is_linux ? azurerm_function_app_flex_consumption.main[0].identity[0].principal_id : null
    ) : (
        local.is_linux ? azurerm_linux_function_app.main[0].identity[0].principal_id : azurerm_windows_function_app.main[0].identity[0].principal_id
    )
}

output "id" {
    value       = local.func_id
    description = "Function App resource ID"
}

output "name" {
    value       = var.name
    description = "Function App name"
}

output "default_hostname" {
    value       = local.func_hostname
    description = "Function App default hostname"
}

output "url" {
    value       = "https://${local.func_hostname}"
    description = "Function App HTTPS URL"
}

output "principal_id" {
    value       = local.func_principal_id
    description = "Function App managed identity principal ID"
}

output "storage_account_name" {
    value       = azurerm_storage_account.func.name
    description = "Storage account name used by the Function App"
}

output "storage_account_id" {
    value       = azurerm_storage_account.func.id
    description = "Storage account resource ID"
}

# -----------------------------------------------------------------------------
# Sensitive outputs for Key Vault storage
# -----------------------------------------------------------------------------

output "storage_connection_string" {
    value       = azurerm_storage_account.func.primary_connection_string
    description = "Storage account connection string"
    sensitive   = true
}

output "secrets_for_keyvault" {
    value = {
        "func-${var.name}-storage-connection-string" = azurerm_storage_account.func.primary_connection_string
        "func-${var.name}-storage-account-name"      = azurerm_storage_account.func.name
        "func-${var.name}-storage-account-key"       = azurerm_storage_account.func.primary_access_key
    }
    description = "Map of secrets ready to store in Key Vault"
    sensitive   = true
}
