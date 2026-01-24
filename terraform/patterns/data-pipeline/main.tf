# terraform/patterns/data-pipeline/main.tf
# Data Pipeline Pattern - Event Hub + Function + Storage + Cosmos DB
# For event-driven data processing pipelines

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = ">= 4.0" }
    azuread = { source = "hashicorp/azuread", version = "~> 2.0" }
    random  = { source = "hashicorp/random", version = "~> 3.0" }
  }
  backend "azurerm" { use_oidc = true }
}

provider "azurerm" {
  features {}
  use_oidc = true
}
provider "azuread" { use_oidc = true }

# Variables
variable "project" { type = string }
variable "environment" { type = string }
variable "name" { type = string }
variable "owners" { type = list(string) }
variable "business_unit" { type = string }
variable "location" {
  type    = string
  default = "eastus"
}

# Sizing
variable "eventhub_sku" {
  type    = string
  default = "Basic"
}
variable "eventhub_capacity" {
  type    = number
  default = 1
}
variable "function_sku" {
  type    = string
  default = "Y1"
}
variable "storage_replication" {
  type    = string
  default = "LRS"
}

# Pattern-specific
variable "partition_count" {
  type    = number
  default = 4
}
variable "message_retention" {
  type    = number
  default = 1
}
variable "runtime" {
  type    = string
  default = "python"
}
variable "enable_mongodb" {
  type    = bool
  default = true
}
variable "enable_diagnostics" {
  type    = bool
  default = false
}
variable "enable_access_review" {
  type    = bool
  default = false
}
variable "purge_protection" {
  type    = bool
  default = false
}
variable "geo_redundant_backup" {
  type    = bool
  default = false
}
variable "access_reviewers" {
  type    = list(string)
  default = []
}
variable "log_analytics_workspace_id" {
  type    = string
  default = ""
}

# Resource Group
module "naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "resource_group"
  name          = var.name
  business_unit = var.business_unit
}

resource "azurerm_resource_group" "main" {
  name     = module.naming.resource_group_name
  location = var.location
  tags     = module.naming.tags
}

# Event Hub (Ingestion)
module "eventhub_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "eventhub"
  name          = "${var.name}-ingest"
  business_unit = var.business_unit
}

module "eventhub" {
  source = "../../modules/eventhub"

  name                = module.eventhub_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku               = var.eventhub_sku
    capacity          = var.eventhub_capacity
    partition_count   = var.partition_count
    message_retention = var.message_retention
  }
  tags = module.naming.tags
}

# Function App (Processor)
module "func_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "function_app"
  name          = "${var.name}-processor"
  business_unit = var.business_unit
}

module "function_app" {
  source = "../../modules/function-app"

  name                = module.func_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku             = var.function_sku
    runtime         = var.runtime
    runtime_version = "3.11"
    os_type         = "Linux"
    app_settings = {
      "EVENTHUB_CONNECTION" = "@Microsoft.KeyVault(VaultName=${module.keyvault_naming.name};SecretName=eventhub-connection-string)"
    }
  }
  tags = module.naming.tags
}

# Storage (Data Lake)
module "storage_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "storage_account"
  name          = "${var.name}data"
  business_unit = var.business_unit
}

resource "azurerm_storage_account" "datalake" {
  name                     = module.storage_naming.name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.storage_replication
  account_kind             = "StorageV2"
  is_hns_enabled           = true  # Enable hierarchical namespace for Data Lake
  min_tls_version          = "TLS1_2"
  tags                     = module.naming.tags
}

resource "azurerm_storage_container" "containers" {
  for_each = toset(["raw", "processed", "errors"])

  name                  = each.value
  storage_account_name  = azurerm_storage_account.datalake.name
  container_access_type = "private"
}

# MongoDB (optional - for processed data)
module "mongodb_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "mongodb"
  name          = "${var.name}-store"
  business_unit = var.business_unit
}

module "mongodb" {
  source = "../../modules/mongodb"
  count  = var.enable_mongodb ? 1 : 0

  name                = module.mongodb_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config              = {}
  tags                = module.naming.tags
}

# Key Vault
module "keyvault_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "keyvault"
  name          = var.name
  business_unit = var.business_unit
}

module "keyvault" {
  source = "../../modules/keyvault"

  name                = module.keyvault_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config              = { sku = "standard", rbac_enabled = true }
  secrets = merge(
    {
      "eventhub-connection-string" = module.eventhub.connection_string
      "storage-connection-string"  = azurerm_storage_account.datalake.primary_connection_string
    },
    var.enable_mongodb ? {
      "mongodb-connection-string" = module.mongodb[0].connection_string
    } : {}
  )
  secrets_user_principal_ids = {
    "processor" = module.function_app.principal_id
  }
  tags = module.naming.tags
}

# Security Groups
module "security_groups" {
  source       = "../../modules/security-groups"
  project      = var.project
  environment  = var.environment
  groups = [
    { suffix = "pipeline-developers", description = "Developers for ${var.name} data pipeline" },
    { suffix = "pipeline-admins", description = "Administrators for ${var.name} data pipeline" },
    { suffix = "data-analysts", description = "Data analysts with read access to ${var.name}" }
  ]
  owner_emails = var.owners
}

# RBAC
module "rbac" {
  source = "../../modules/rbac-assignments"
  assignments = concat(
    [
      {
        principal_id         = module.security_groups.group_ids["pipeline-developers"]
        role_definition_name = "Website Contributor"
        scope                = module.function_app.id
      },
      {
        principal_id         = module.security_groups.group_ids["pipeline-developers"]
        role_definition_name = "Azure Event Hubs Data Sender"
        scope                = module.eventhub.namespace_id
      },
      {
        principal_id         = module.security_groups.group_ids["pipeline-admins"]
        role_definition_name = "Key Vault Secrets Officer"
        scope                = module.keyvault.vault_id
      },
      {
        principal_id         = module.security_groups.group_ids["data-analysts"]
        role_definition_name = "Storage Blob Data Reader"
        scope                = azurerm_storage_account.datalake.id
      },
      {
        principal_id         = module.security_groups.group_ids["pipeline-developers"]
        role_definition_name = "Storage Blob Data Contributor"
        scope                = azurerm_storage_account.datalake.id
      },
      # Function app needs Event Hub receiver and storage writer
      {
        principal_id         = module.function_app.principal_id
        role_definition_name = "Azure Event Hubs Data Receiver"
        scope                = module.eventhub.namespace_id
      },
      {
        principal_id         = module.function_app.principal_id
        role_definition_name = "Storage Blob Data Contributor"
        scope                = azurerm_storage_account.datalake.id
      }
    ],
    var.enable_mongodb ? [
      {
        principal_id         = module.function_app.principal_id
        role_definition_name = "Cosmos DB Operator"
        scope                = module.mongodb[0].account_id
      },
      {
        principal_id         = module.security_groups.group_ids["data-analysts"]
        role_definition_name = "Cosmos DB Account Reader Role"
        scope                = module.mongodb[0].account_id
      }
    ] : []
  )

  skip_service_principal_check = true  # For managed identity
}

# Access Review (prod only)
module "access_review" {
  source = "../../modules/access-review"
  count  = var.enable_access_review && length(var.access_reviewers) > 0 ? 1 : 0

  group_id        = module.security_groups.group_ids["pipeline-admins"]
  group_name      = module.security_groups.group_names["pipeline-admins"]
  reviewer_emails = var.access_reviewers
  frequency       = "quarterly"
}

# Diagnostics (staging/prod)
module "diagnostics" {
  source = "../../modules/diagnostic-settings"
  count  = var.enable_diagnostics && var.log_analytics_workspace_id != "" ? 1 : 0

  name                       = module.func_naming.name
  target_resource_id         = module.function_app.id
  log_analytics_workspace_id = var.log_analytics_workspace_id
}

# Outputs
output "eventhub" {
  value = {
    namespace = module.eventhub.namespace_name
    name      = module.eventhub.eventhub_name
  }
}

output "processor" {
  value = {
    name = module.function_app.name
    url  = module.function_app.url
  }
}

output "datalake" {
  value = {
    name       = azurerm_storage_account.datalake.name
    endpoint   = azurerm_storage_account.datalake.primary_dfs_endpoint
    containers = ["raw", "processed", "errors"]
  }
}

output "mongodb" {
  value = var.enable_mongodb ? {
    endpoint = module.mongodb[0].endpoint
  } : null
}

output "keyvault" { value = { name = module.keyvault.vault_name, uri = module.keyvault.vault_uri } }
output "resource_group" { value = azurerm_resource_group.main.name }
output "security_groups" { value = module.security_groups.group_names }

output "access_info" {
  value = <<-EOT
    Data Pipeline: ${var.name}

    Ingestion:
      Event Hub: ${module.eventhub.namespace_name}/${module.eventhub.eventhub_name}

    Processing:
      Function App: ${module.function_app.name}

    Storage:
      Data Lake: ${azurerm_storage_account.datalake.name}
      Containers: raw, processed, errors
      ${var.enable_mongodb ? "MongoDB: ${module.mongodb[0].endpoint}" : ""}

    Key Vault: ${module.keyvault.vault_name}

    Security Groups:
    - Developers: ${module.security_groups.group_names["pipeline-developers"]}
    - Admins: ${module.security_groups.group_names["pipeline-admins"]}
    - Analysts: ${module.security_groups.group_names["data-analysts"]}
  EOT
}
