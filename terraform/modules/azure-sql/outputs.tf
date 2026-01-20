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

# -----------------------------------------------------------------------------
# Sensitive outputs for Key Vault storage
# -----------------------------------------------------------------------------

output "admin_login" {
    value       = local.admin_login
    description = "SQL Server administrator login username"
}

output "admin_password" {
    value       = random_password.admin.result
    description = "SQL Server administrator password"
    sensitive   = true
}

output "connection_string_template" {
    value       = "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Database={database};User ID=${local.admin_login};Encrypt=true;Connection Timeout=30;"
    description = "Connection string template (replace {database} with actual database name, add Password)"
}

# Full connection strings per database (for Key Vault storage)
output "connection_strings" {
    value = { for k, v in azurerm_mssql_database.databases : k =>
        "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Database=${v.name};User ID=${local.admin_login};Password=${random_password.admin.result};Encrypt=true;TrustServerCertificate=false;Connection Timeout=30;"
    }
    description = "Full connection strings per database (include password - for Key Vault only)"
    sensitive   = true
}

# Secrets map ready for Key Vault storage
output "secrets_for_keyvault" {
    value = merge(
        {
            "sql-admin-username" = local.admin_login
            "sql-admin-password" = random_password.admin.result
            "sql-server-fqdn"    = azurerm_mssql_server.main.fully_qualified_domain_name
        },
        { for k, v in azurerm_mssql_database.databases :
            "sql-connection-string-${k}" => "Server=tcp:${azurerm_mssql_server.main.fully_qualified_domain_name},1433;Database=${v.name};User ID=${local.admin_login};Password=${random_password.admin.result};Encrypt=true;TrustServerCertificate=false;Connection Timeout=30;"
        }
    )
    description = "Map of secrets ready to store in Key Vault"
    sensitive   = true
}
