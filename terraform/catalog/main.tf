terraform {
    required_version = ">= 1.5.0"
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

    backend "azurerm" {
        use_oidc = true
    }
}

provider "azurerm" {
    features {
        resource_group {
            prevent_deletion_if_contains_resources = false
        }
        key_vault {
            purge_soft_delete_on_destroy = true
        }
    }
    use_oidc = true
}

variable "config_file" {
    description = "Path to YAML configuration file"
    type        = string
}

locals {
    config   = yamldecode(file(var.config_file))
    metadata = local.config.metadata
    resources = local.config.resources

    common_tags = merge(
        {
            Project       = local.metadata.project_name
            Environment   = local.metadata.environment
            BusinessUnit  = local.metadata.business_unit
            CostCenter    = local.metadata.cost_center
            Owner         = local.metadata.owner_email
            ManagedBy     = "Terraform-SelfService"
        },
        lookup(local.metadata, "tags", {})
    )

    resource_group_name = "rg-${local.metadata.project_name}-${local.metadata.environment}"
    location            = lookup(local.metadata, "location", "eastus")

    # Use resource name as key (stable) instead of index (shifts when resources removed)
    postgresql_resources    = { for r in local.resources : r.name => r if r.type == "postgresql" }
    mongodb_resources       = { for r in local.resources : r.name => r if r.type == "mongodb" }
    keyvault_resources      = { for r in local.resources : r.name => r if r.type == "keyvault" }
    aks_namespace_resources = { for r in local.resources : r.name => r if r.type == "aks_namespace" }
    eventhub_resources      = { for r in local.resources : r.name => r if r.type == "eventhub" }
    function_resources      = { for r in local.resources : r.name => r if r.type == "function_app" }
    vm_resources            = { for r in local.resources : r.name => r if r.type == "linux_vm" }
    storage_resources        = { for r in local.resources : r.name => r if r.type == "storage_account" }
    static_web_app_resources = { for r in local.resources : r.name => r if r.type == "static_web_app" }
    azure_sql_resources      = { for r in local.resources : r.name => r if r.type == "azure_sql" }
}

resource "azurerm_resource_group" "main" {
    name     = local.resource_group_name
    location = local.location
    tags     = local.common_tags
}

module "postgresql" {
    source = "../modules/postgresql"

    for_each = local.postgresql_resources

    name                = "${local.metadata.project_name}-${each.key}-${local.metadata.environment}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = each.value.config
    tags                = local.common_tags
}

module "mongodb" {
    source = "../modules/mongodb"

    for_each = local.mongodb_resources

    name                = "${local.metadata.project_name}-${each.key}-${local.metadata.environment}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = each.value.config
    tags                = local.common_tags
}

module "keyvault" {
    source = "../modules/keyvault"

    for_each = local.keyvault_resources

    name                = "${local.metadata.project_name}-${each.key}-${local.metadata.environment}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = each.value.config
    tags                = local.common_tags
}

module "storage_account" {
    source = "../modules/storage-account"

    for_each = local.storage_resources

    name                = lower("${local.metadata.project_name}${each.key}${local.metadata.environment}")
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = each.value.config
    tags                = local.common_tags
}

module "static_web_app" {
    source = "../modules/static-web-app"

    for_each = local.static_web_app_resources

    name                = "swa-${local.metadata.project_name}-${each.key}-${local.metadata.environment}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = lookup(each.value, "config", {})
    tags                = local.common_tags
}

module "function_app" {
    source = "../modules/function-app"

    for_each = local.function_resources

    name                = "func-${local.metadata.project_name}-${each.key}-${local.metadata.environment}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = lookup(each.value, "config", {})
    tags                = local.common_tags
}

module "azure_sql" {
    source = "../modules/azure-sql"

    for_each = local.azure_sql_resources

    name                = "sql-${local.metadata.project_name}-${each.key}-${local.metadata.environment}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = lookup(each.value, "config", {})
    tags                = local.common_tags
}

output "resource_group" {
    value = {
        name     = azurerm_resource_group.main.name
        location = azurerm_resource_group.main.location
        id       = azurerm_resource_group.main.id
    }
}

output "postgresql_servers" {
    value = { for k, v in module.postgresql : k => {
        fqdn      = v.server_fqdn
        server_id = v.server_id
        database  = v.database_name
    }}
}

output "storage_accounts" {
    value = { for k, v in module.storage_account : k => {
        name             = v.name
        primary_endpoint = v.primary_blob_endpoint
        containers       = v.containers
    }}
}

output "static_web_apps" {
    value = { for k, v in module.static_web_app : k => {
        name              = v.name
        default_host_name = v.default_host_name
        url               = "https://${v.default_host_name}"
    }}
}

output "function_apps" {
    value = { for k, v in module.function_app : k => {
        name             = v.name
        default_hostname = v.default_hostname
        url              = "https://${v.default_hostname}"
        principal_id     = v.principal_id
    }}
}

output "azure_sql_servers" {
    value = { for k, v in module.azure_sql : k => {
        server_name  = v.server_name
        server_fqdn  = v.server_fqdn
        databases    = v.databases
        principal_id = v.principal_id
    }}
}
