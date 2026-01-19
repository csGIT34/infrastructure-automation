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

resource "random_password" "admin" {
    length           = 32
    special          = true
    override_special = "!#$%&*()-_=+[]{}<>:?"
}

locals {
    sku_name     = lookup(var.config, "sku", "Basic")
    max_size_gb  = lookup(var.config, "max_size_gb", 2)
    collation    = lookup(var.config, "collation", "SQL_Latin1_General_CP1_CI_AS")
    databases    = lookup(var.config, "databases", [{ name = "default" }])
    admin_login  = lookup(var.config, "admin_login", "sqladmin")

    # Firewall rules - allow Azure services by default
    firewall_rules = lookup(var.config, "firewall_rules", [
        {
            name             = "AllowAzureServices"
            start_ip_address = "0.0.0.0"
            end_ip_address   = "0.0.0.0"
        }
    ])
}

resource "azurerm_mssql_server" "main" {
    name                         = var.name
    resource_group_name          = var.resource_group_name
    location                     = var.location
    version                      = lookup(var.config, "version", "12.0")
    administrator_login          = local.admin_login
    administrator_login_password = random_password.admin.result

    minimum_tls_version = "1.2"

    azuread_administrator {
        login_username = lookup(var.config, "aad_admin_login", null)
        object_id      = lookup(var.config, "aad_admin_object_id", null)
    }

    identity {
        type = "SystemAssigned"
    }

    tags = var.tags

    lifecycle {
        ignore_changes = [
            azuread_administrator
        ]
    }
}

resource "azurerm_mssql_firewall_rule" "rules" {
    for_each = { for r in local.firewall_rules : r.name => r }

    name             = each.value.name
    server_id        = azurerm_mssql_server.main.id
    start_ip_address = each.value.start_ip_address
    end_ip_address   = each.value.end_ip_address
}

resource "azurerm_mssql_database" "databases" {
    for_each = { for db in local.databases : db.name => db }

    name           = each.value.name
    server_id      = azurerm_mssql_server.main.id
    collation      = lookup(each.value, "collation", local.collation)
    max_size_gb    = lookup(each.value, "max_size_gb", local.max_size_gb)
    sku_name       = lookup(each.value, "sku", local.sku_name)
    zone_redundant = lookup(each.value, "zone_redundant", false)

    short_term_retention_policy {
        retention_days = lookup(each.value, "backup_retention_days", 7)
    }

    tags = var.tags
}
