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

    postgresql_resources    = [for idx, r in local.resources : merge(r, { index = idx }) if r.type == "postgresql"]
    mongodb_resources       = [for idx, r in local.resources : merge(r, { index = idx }) if r.type == "mongodb"]
    keyvault_resources      = [for idx, r in local.resources : merge(r, { index = idx }) if r.type == "keyvault"]
    aks_namespace_resources = [for idx, r in local.resources : merge(r, { index = idx }) if r.type == "aks_namespace"]
    eventhub_resources      = [for idx, r in local.resources : merge(r, { index = idx }) if r.type == "eventhub"]
    function_resources      = [for idx, r in local.resources : merge(r, { index = idx }) if r.type == "function_app"]
    vm_resources            = [for idx, r in local.resources : merge(r, { index = idx }) if r.type == "linux_vm"]
    storage_resources       = [for idx, r in local.resources : merge(r, { index = idx }) if r.type == "storage_account"]
    static_web_app_resources = [for idx, r in local.resources : merge(r, { index = idx }) if r.type == "static_web_app"]
}

resource "azurerm_resource_group" "main" {
    name     = local.resource_group_name
    location = local.location
    tags     = local.common_tags
}

module "postgresql" {
    source = "../modules/postgresql"

    for_each = { for r in local.postgresql_resources : r.index => r }

    name                = "${local.metadata.project_name}-${each.value.name}-${local.metadata.environment}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = each.value.config
    tags                = local.common_tags
}

module "mongodb" {
    source = "../modules/mongodb"

    for_each = { for r in local.mongodb_resources : r.index => r }

    name                = "${local.metadata.project_name}-${each.value.name}-${local.metadata.environment}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = each.value.config
    tags                = local.common_tags
}

module "keyvault" {
    source = "../modules/keyvault"

    for_each = { for r in local.keyvault_resources : r.index => r }

    name                = "${local.metadata.project_name}-${each.value.name}-${local.metadata.environment}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = each.value.config
    tags                = local.common_tags
}

module "storage_account" {
    source = "../modules/storage-account"

    for_each = { for r in local.storage_resources : r.index => r }

    name                = lower("${local.metadata.project_name}${each.value.name}${local.metadata.environment}")
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = each.value.config
    tags                = local.common_tags
}

module "static_web_app" {
    source = "../modules/static-web-app"

    for_each = { for r in local.static_web_app_resources : r.index => r }

    name                = "swa-${local.metadata.project_name}-${each.value.name}-${local.metadata.environment}"
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
