output "server_id" {
    value       = azurerm_mssql_server.main.id
    description = "Azure SQL Server resource ID"
}

output "server_fqdn" {
    value       = azurerm_mssql_server.main.fully_qualified_domain_name
    description = "Azure SQL Server fully qualified domain name"
}

output "server_name" {
    value       = azurerm_mssql_server.main.name
    description = "Azure SQL Server name"
}

output "databases" {
    value       = { for k, v in azurerm_mssql_database.databases : k => {
        id   = v.id
        name = v.name
    }}
    description = "Map of database names to their IDs"
}

output "principal_id" {
    value       = azurerm_mssql_server.main.identity[0].principal_id
    description = "SQL Server managed identity principal ID"
}

output "connection_string" {
    value       = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Database={database};User ID=${local.admin_login};Encrypt=true;Connection Timeout=30;"
    description = "Connection string template (replace {database} with actual database name)"
    sensitive   = true
}
