# terraform/patterns/aks-namespace/main.tf
# AKS Namespace Pattern - Kubernetes namespace with RBAC and resource quotas

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

variable "aks_cluster_name" { type = string }
variable "aks_resource_group" { type = string }

# Sizing-resolved quotas
variable "cpu_limit" {
  type    = string
  default = "2"
}
variable "memory_limit" {
  type    = string
  default = "4Gi"
}
variable "pod_limit" {
  type    = number
  default = 20
}

# Kubernetes provider config
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

# Naming
module "naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "aks_namespace"
  name          = var.name
  business_unit = var.business_unit
}

# AKS Namespace (base module)
module "aks_namespace" {
  source = "../../modules/aks-namespace"

  name = module.naming.name
  config = {
    cpu_limit    = var.cpu_limit
    memory_limit = var.memory_limit
    pod_limit    = var.pod_limit
  }
}

# Security Groups
module "security_groups" {
  source       = "../../modules/security-groups"
  project      = var.project
  environment  = var.environment
  groups = [
    { suffix = "k8s-viewers", description = "View access to ${var.name} namespace" },
    { suffix = "k8s-editors", description = "Edit access to ${var.name} namespace" },
    { suffix = "k8s-admins", description = "Admin access to ${var.name} namespace" }
  ]
  owner_emails = var.owners
}

# RBAC - Azure Kubernetes Service RBAC roles
module "rbac" {
  source = "../../modules/rbac-assignments"
  assignments = [
    {
      principal_id         = module.security_groups.group_ids["k8s-viewers"]
      role_definition_name = "Azure Kubernetes Service RBAC Reader"
      scope                = "${data.azurerm_kubernetes_cluster.aks.id}/namespaces/${module.aks_namespace.namespace_name}"
    },
    {
      principal_id         = module.security_groups.group_ids["k8s-editors"]
      role_definition_name = "Azure Kubernetes Service RBAC Writer"
      scope                = "${data.azurerm_kubernetes_cluster.aks.id}/namespaces/${module.aks_namespace.namespace_name}"
    },
    {
      principal_id         = module.security_groups.group_ids["k8s-admins"]
      role_definition_name = "Azure Kubernetes Service RBAC Admin"
      scope                = "${data.azurerm_kubernetes_cluster.aks.id}/namespaces/${module.aks_namespace.namespace_name}"
    }
  ]
}

# Outputs
output "namespace" {
  value = {
    name        = module.aks_namespace.namespace_name
    cluster     = var.aks_cluster_name
    cpu_limit   = var.cpu_limit
    memory_limit = var.memory_limit
  }
}
output "security_groups" { value = module.security_groups.group_names }
output "access_info" {
  value = <<-EOT
    Namespace: ${module.aks_namespace.namespace_name}
    Cluster: ${var.aks_cluster_name}

    Resource Quotas:
    - CPU: ${var.cpu_limit}
    - Memory: ${var.memory_limit}
    - Pods: ${var.pod_limit}

    To access:
      az aks get-credentials --resource-group ${var.aks_resource_group} --name ${var.aks_cluster_name}
      kubectl config set-context --current --namespace=${module.aks_namespace.namespace_name}
  EOT
}
