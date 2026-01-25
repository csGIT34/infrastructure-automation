# Test fixture: Data Pipeline pattern
#
# Tests Event Hub + Function App + Storage + Key Vault + Security Groups + Access Reviews
# Skips MongoDB for faster testing (enable_mongodb = false)

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

variable "resource_suffix" {
  type = string
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "owner_email" {
  description = "Owner email for security groups (optional for tests)"
  type        = string
  default     = ""
}

locals {
  project       = "tftest-${var.resource_suffix}"
  environment   = "dev"
  name          = "dpipe"
  business_unit = "engineering"
  pattern_name  = "data-pipeline"
}

# Resource Group
module "naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "resource_group"
  name          = local.name
  business_unit = local.business_unit
  pattern_name  = local.pattern_name
}

resource "azurerm_resource_group" "main" {
  name     = module.naming.resource_group_name
  location = var.location
  tags     = module.naming.tags
}

# Event Hub (Ingestion)
module "eventhub_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "eventhub"
  name          = "${local.name}-ingest"
  business_unit = local.business_unit
}

module "eventhub" {
  source = "../../../../modules/eventhub"

  name                = module.eventhub_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku               = "Basic"
    capacity          = 1
    partition_count   = 2
    message_retention = 1
  }
  tags = module.naming.tags
}

# Function App (Processor)
module "func_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "function_app"
  name          = "${local.name}-proc"
  business_unit = local.business_unit
}

module "function_app" {
  source = "../../../../modules/function-app"

  name                = module.func_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku             = "FC1"  # Flex Consumption
    runtime         = "python"
    runtime_version = "3.11"
    os_type         = "Linux"
  }
  tags = module.naming.tags
}

# Storage (Data Lake)
module "storage_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "storage_account"
  name          = "${local.name}data"
  business_unit = local.business_unit
}

resource "azurerm_storage_account" "datalake" {
  name                     = module.storage_naming.name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
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

# Key Vault
module "keyvault_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "keyvault"
  name          = local.name
  business_unit = local.business_unit
  pattern_name  = local.pattern_name
}

module "keyvault" {
  source = "../../../../modules/keyvault"

  name                = module.keyvault_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config              = { sku = "standard", rbac_enabled = true }
  secrets = {
    "eventhub-connection-string" = module.eventhub.default_connection_string
    "storage-connection-string"  = azurerm_storage_account.datalake.primary_connection_string
  }
  secrets_user_principal_ids = { "processor" = module.function_app.principal_id }
  tags = module.naming.tags
}

# Security Groups
module "security_groups" {
  source = "../../../../modules/security-groups"

  project     = local.project
  environment = local.environment
  groups = [
    { suffix = "pipeline-developers", description = "Developers for ${local.name} data pipeline (test)" },
    { suffix = "pipeline-admins", description = "Administrators for ${local.name} data pipeline (test)" },
    { suffix = "data-analysts", description = "Data analysts with read access to ${local.name} (test)" }
  ]
  # Only pass owner_emails if owner_email is set, otherwise empty list
  owner_emails = var.owner_email != "" ? [var.owner_email] : []
}

# RBAC Assignments for Security Groups (no skip check needed)
module "rbac_groups" {
  source = "../../../../modules/rbac-assignments"

  assignments = [
    {
      principal_id         = module.security_groups.group_ids["pipeline-developers"]
      role_definition_name = "Website Contributor"
      scope                = module.function_app.id
      description          = "Developers - function app access (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["pipeline-developers"]
      role_definition_name = "Azure Event Hubs Data Sender"
      scope                = module.eventhub.namespace_id
      description          = "Developers - event hub send access (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["pipeline-admins"]
      role_definition_name = "Key Vault Secrets Officer"
      scope                = module.keyvault.vault_id
      description          = "Admins - secrets management (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["data-analysts"]
      role_definition_name = "Storage Blob Data Reader"
      scope                = azurerm_storage_account.datalake.id
      description          = "Analysts - storage read access (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["pipeline-developers"]
      role_definition_name = "Storage Blob Data Contributor"
      scope                = azurerm_storage_account.datalake.id
      description          = "Developers - storage write access (test)"
    }
  ]
}

# RBAC Assignments for Managed Identity (skip check needed)
module "rbac_identity" {
  source = "../../../../modules/rbac-assignments"

  assignments = [
    {
      principal_id         = module.function_app.principal_id
      role_definition_name = "Azure Event Hubs Data Receiver"
      scope                = module.eventhub.namespace_id
      description          = "Function - event hub receive (test)"
    },
    {
      principal_id         = module.function_app.principal_id
      role_definition_name = "Storage Blob Data Contributor"
      scope                = azurerm_storage_account.datalake.id
      description          = "Function - storage write (test)"
    }
  ]

  skip_service_principal_check = true
}

# Access Reviews for Security Groups
module "access_review_developers" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["pipeline-developers"]
  group_name = module.security_groups.group_names["pipeline-developers"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

module "access_review_admins" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["pipeline-admins"]
  group_name = module.security_groups.group_names["pipeline-admins"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

module "access_review_analysts" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["data-analysts"]
  group_name = module.security_groups.group_names["data-analysts"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

# Outputs
output "eventhub" {
  value = {
    namespace = module.eventhub.namespace_name
    hubs      = module.eventhub.hubs
  }
}

output "processor" {
  value = {
    name         = module.function_app.name
    url          = module.function_app.url
    principal_id = module.function_app.principal_id
  }
}

output "datalake" {
  value = {
    name       = azurerm_storage_account.datalake.name
    endpoint   = azurerm_storage_account.datalake.primary_dfs_endpoint
    containers = ["raw", "processed", "errors"]
  }
}

output "keyvault" {
  value = {
    name = module.keyvault.vault_name
    uri  = module.keyvault.vault_uri
    id   = module.keyvault.vault_id
  }
}

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "security_groups" {
  value = module.security_groups.group_names
}

output "access_reviews" {
  value = {
    developers = module.access_review_developers.review_name
    admins     = module.access_review_admins.review_name
    analysts   = module.access_review_analysts.review_name
  }
}

output "access_info" {
  value = <<-EOT
    Data Pipeline Pattern Test Results
    ===================================

    Event Hub (Ingestion):
    - Namespace: ${module.eventhub.namespace_name}

    Function App (Processor):
    - Name: ${module.function_app.name}
    - URL: ${module.function_app.url}

    Data Lake (Storage):
    - Name: ${azurerm_storage_account.datalake.name}
    - Containers: raw, processed, errors

    Key Vault:
    - Name: ${module.keyvault.vault_name}
    - URI: ${module.keyvault.vault_uri}

    Security Groups:
    - Developers: ${module.security_groups.group_names["pipeline-developers"]}
    - Admins: ${module.security_groups.group_names["pipeline-admins"]}
    - Analysts: ${module.security_groups.group_names["data-analysts"]}

    Access Reviews:
    - ${module.access_review_developers.review_name}
    - ${module.access_review_admins.review_name}
    - ${module.access_review_analysts.review_name}
  EOT
}
