output "server_fqdn" {
    value       = azurerm_postgresql_flexible_server.main.fqdn
    description = "PostgreSQL server FQDN"
}

output "server_id" {
    value       = azurerm_postgresql_flexible_server.main.id
    description = "PostgreSQL server resource ID"
}

output "database_name" {
    value       = azurerm_postgresql_flexible_server_database.main.name
    description = "PostgreSQL database name"
}
