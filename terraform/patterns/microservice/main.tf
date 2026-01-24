# terraform/patterns/microservice/main.tf
# Microservice Pattern - AKS Namespace + Function App + Event Hub + Storage
# For event-driven microservices

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm    = { source = "hashicorp/azurerm", version = ">= 4.0" }
    azuread    = { source = "hashicorp/azuread", version = "~> 2.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.0" }
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

# AKS cluster info
variable "aks_cluster_name" { type = string }
variable "aks_resource_group" { type = string }

# Sizing
variable "cpu_limit" {
  type    = string
  default = "2"
}
variable "memory_limit" {
  type    = string
  default = "4Gi"
}
variable "eventhub_sku" {
  type    = string
  default = "Basic"
}

# Pattern-specific
variable "enable_eventhub" {
  type    = bool
  default = true
}
variable "enable_storage" {
  type    = bool
  default = true
}
variable "enable_diagnostics" {
  type    = bool
  default = false
}
variable "log_analytics_workspace_id" {
  type    = string
  default = ""
}

# Kubernetes provider
data "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_cluster_name
  resource_group_name = var.aks_resource_group
}

provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.aks.kube_config[0].host
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
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

# AKS Namespace
module "ns_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "aks_namespace"
  name          = var.name
  business_unit = var.business_unit
}

module "aks_namespace" {
  source = "../../modules/aks-namespace"

  name = module.ns_naming.name
  config = {
    cpu_limit    = var.cpu_limit
    memory_limit = var.memory_limit
    pod_limit    = 50
  }
}

# Event Hub (optional)
module "eventhub_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "eventhub"
  name          = var.name
  business_unit = var.business_unit
}

module "eventhub" {
  source = "../../modules/eventhub"
  count  = var.enable_eventhub ? 1 : 0

  name                = module.eventhub_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config              = { sku = var.eventhub_sku }
  tags                = module.naming.tags
}

# Storage (optional)
module "storage_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "storage_account"
  name          = var.name
  business_unit = var.business_unit
}

resource "azurerm_storage_account" "main" {
  count = var.enable_storage ? 1 : 0

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
    var.enable_eventhub ? { "eventhub-connection-string" = module.eventhub[0].connection_string } : {},
    var.enable_storage ? { "storage-connection-string" = azurerm_storage_account.main[0].primary_connection_string } : {}
  )
  tags = module.naming.tags
}

# Security Groups
module "security_groups" {
  source       = "../../modules/security-groups"
  project      = var.project
  environment  = var.environment
  groups = [
    { suffix = "ms-developers", description = "Developers for ${var.name} microservice" },
    { suffix = "ms-admins", description = "Administrators for ${var.name} microservice" }
  ]
  owner_emails = var.owners
}

# RBAC
module "rbac" {
  source = "../../modules/rbac-assignments"
  assignments = concat(
    [
      {
        principal_id         = module.security_groups.group_ids["ms-developers"]
        role_definition_name = "Azure Kubernetes Service RBAC Writer"
        scope                = "${data.azurerm_kubernetes_cluster.aks.id}/namespaces/${module.aks_namespace.namespace_name}"
      },
      {
        principal_id         = module.security_groups.group_ids["ms-admins"]
        role_definition_name = "Azure Kubernetes Service RBAC Admin"
        scope                = "${data.azurerm_kubernetes_cluster.aks.id}/namespaces/${module.aks_namespace.namespace_name}"
      },
      {
        principal_id         = module.security_groups.group_ids["ms-admins"]
        role_definition_name = "Key Vault Secrets Officer"
        scope                = module.keyvault.vault_id
      }
    ],
    var.enable_eventhub ? [
      {
        principal_id         = module.security_groups.group_ids["ms-developers"]
        role_definition_name = "Azure Event Hubs Data Sender"
        scope                = module.eventhub[0].namespace_id
      }
    ] : [],
    var.enable_storage ? [
      {
        principal_id         = module.security_groups.group_ids["ms-developers"]
        role_definition_name = "Storage Blob Data Contributor"
        scope                = azurerm_storage_account.main[0].id
      }
    ] : []
  )
}

# Outputs
output "namespace" {
  value = {
    name    = module.aks_namespace.namespace_name
    cluster = var.aks_cluster_name
  }
}

output "eventhub" {
  value = var.enable_eventhub ? {
    namespace = module.eventhub[0].namespace_name
    name      = module.eventhub[0].eventhub_name
  } : null
}

output "storage" {
  value = var.enable_storage ? {
    name     = azurerm_storage_account.main[0].name
    endpoint = azurerm_storage_account.main[0].primary_blob_endpoint
  } : null
}

output "keyvault" { value = { name = module.keyvault.vault_name, uri = module.keyvault.vault_uri } }
output "resource_group" { value = azurerm_resource_group.main.name }
output "security_groups" { value = module.security_groups.group_names }
