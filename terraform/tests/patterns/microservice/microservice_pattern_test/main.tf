# Test fixture: Microservice pattern
#
# Tests Event Hub + Storage + Key Vault + Security Groups + Access Reviews
# Note: AKS namespace is skipped as it requires an existing AKS cluster

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
    msgraph = {
      source  = "microsoft/msgraph"
      version = "~> 0.2"
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
  description = "Owner email for security groups"
  type        = string
}

locals {
  project       = "tftest-${var.resource_suffix}"
  environment   = "dev"
  name          = "ms"
  business_unit = "engineering"
  pattern_name  = "microservice"
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

# Event Hub
module "eventhub_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "eventhub"
  name          = local.name
  business_unit = local.business_unit
}

module "eventhub" {
  source = "../../../../modules/eventhub"

  name                = module.eventhub_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config              = { sku = "Basic" }
  tags                = module.naming.tags
}

# Storage Account
module "storage_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "storage_account"
  name          = local.name
  business_unit = local.business_unit
}

resource "azurerm_storage_account" "main" {
  name                     = module.storage_naming.name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = module.naming.tags
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
    "storage-connection-string"  = azurerm_storage_account.main.primary_connection_string
  }
  tags = module.naming.tags
}

# Security Groups
module "security_groups" {
  source = "../../../../modules/security-groups"

  project     = local.project
  environment = local.environment
  groups = [
    { suffix = "ms-developers", description = "Developers for ${local.name} microservice (test)" },
    { suffix = "ms-admins", description = "Administrators for ${local.name} microservice (test)" }
  ]
  owner_emails = [var.owner_email]
}

# RBAC Assignments
module "rbac" {
  source = "../../../../modules/rbac-assignments"

  assignments = [
    {
      principal_id         = module.security_groups.group_ids["ms-admins"]
      role_definition_name = "Key Vault Secrets Officer"
      scope                = module.keyvault.vault_id
      description          = "Admins - secrets management (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["ms-developers"]
      role_definition_name = "Azure Event Hubs Data Sender"
      scope                = module.eventhub.namespace_id
      description          = "Developers - Event Hub send access (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["ms-developers"]
      role_definition_name = "Storage Blob Data Contributor"
      scope                = azurerm_storage_account.main.id
      description          = "Developers - Storage access (test)"
    }
  ]
}

# Access Reviews for Security Groups
module "access_review_developers" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["ms-developers"]
  group_name = module.security_groups.group_names["ms-developers"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

module "access_review_admins" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["ms-admins"]
  group_name = module.security_groups.group_names["ms-admins"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

# Outputs
output "eventhub" {
  value = {
    namespace = module.eventhub.namespace_name
    id        = module.eventhub.namespace_id
  }
}

output "storage" {
  value = {
    name     = azurerm_storage_account.main.name
    endpoint = azurerm_storage_account.main.primary_blob_endpoint
    id       = azurerm_storage_account.main.id
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
  }
}

output "access_info" {
  value = <<-EOT
    Microservice Pattern Test Results
    ==================================

    Event Hub:
    - Namespace: ${module.eventhub.namespace_name}

    Storage Account:
    - Name: ${azurerm_storage_account.main.name}
    - Endpoint: ${azurerm_storage_account.main.primary_blob_endpoint}

    Key Vault:
    - Name: ${module.keyvault.vault_name}
    - URI: ${module.keyvault.vault_uri}

    Security Groups:
    - Developers: ${module.security_groups.group_names["ms-developers"]}
    - Admins: ${module.security_groups.group_names["ms-admins"]}

    Access Reviews:
    - ${module.access_review_developers.review_name}
    - ${module.access_review_admins.review_name}

    Note: AKS namespace not tested (requires existing AKS cluster)
  EOT
}
