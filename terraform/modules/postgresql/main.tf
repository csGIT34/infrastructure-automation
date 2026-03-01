# terraform/modules/postgresql/main.tf
# Creates an Azure PostgreSQL Flexible Server with database

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

resource "random_password" "admin" {
  length  = 24
  special = true
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = var.postgresql_version
  administrator_login           = var.admin_username
  administrator_password        = random_password.admin.result
  sku_name                      = var.sku_name
  storage_mb                    = var.storage_mb
  backup_retention_days         = var.backup_retention_days
  geo_redundant_backup_enabled  = var.geo_redundant_backup
  zone                          = var.availability_zone
  public_network_access_enabled = var.public_network_access_enabled
  tags                          = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

# Firewall rule to allow Azure services (when public access is enabled)
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure" {
  count = var.public_network_access_enabled ? 1 : 0

  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Additional firewall rules
resource "azurerm_postgresql_flexible_server_firewall_rule" "rules" {
  for_each = var.public_network_access_enabled ? var.firewall_rules : {}

  name             = each.key
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = each.value.start_ip
  end_ip_address   = each.value.end_ip
}

resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
