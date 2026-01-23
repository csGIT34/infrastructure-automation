terraform {
    required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = ">= 4.0"
        }
        random = {
            source  = "hashicorp/random"
            version = "~> 3.0"
        }
    }
}

resource "random_password" "admin" {
    length  = 32
    special = true
}

resource "azurerm_postgresql_flexible_server" "main" {
    name                = var.name
    resource_group_name = var.resource_group_name
    location            = var.location
    version             = lookup(var.config, "version", "14")

    administrator_login    = "psqladmin"
    administrator_password = random_password.admin.result

    sku_name   = lookup(var.config, "sku", "B_Standard_B1ms")
    storage_mb = lookup(var.config, "storage_mb", 32768)

    backup_retention_days        = lookup(var.config, "backup_retention_days", 7)
    geo_redundant_backup_enabled = lookup(var.config, "geo_redundant_backup", false)

    tags = var.tags
}

resource "azurerm_postgresql_flexible_server_database" "main" {
    name      = "${var.name}-db"
    server_id = azurerm_postgresql_flexible_server.main.id
    charset   = "UTF8"
    collation = "en_US.utf8"
}
