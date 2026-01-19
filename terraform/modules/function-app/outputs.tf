output "id" {
    value       = local.os_type == "Linux" ? azurerm_linux_function_app.main[0].id : azurerm_windows_function_app.main[0].id
    description = "Function App resource ID"
}

output "name" {
    value       = var.name
    description = "Function App name"
}

output "default_hostname" {
    value       = local.os_type == "Linux" ? azurerm_linux_function_app.main[0].default_hostname : azurerm_windows_function_app.main[0].default_hostname
    description = "Function App default hostname"
}

output "principal_id" {
    value       = local.os_type == "Linux" ? azurerm_linux_function_app.main[0].identity[0].principal_id : azurerm_windows_function_app.main[0].identity[0].principal_id
    description = "Function App managed identity principal ID"
}

output "storage_account_name" {
    value       = azurerm_storage_account.func.name
    description = "Storage account name used by the Function App"
}
