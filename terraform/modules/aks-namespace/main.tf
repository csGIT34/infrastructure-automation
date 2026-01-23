terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
  }
}

variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "config" { type = any }
variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  cluster_name = lookup(var.config, "cluster_name", "")

  # Resource quotas
  cpu_limit     = lookup(var.config, "cpu_limit", "2")
  memory_limit  = lookup(var.config, "memory_limit", "4Gi")
  storage_limit = lookup(var.config, "storage_limit", "10Gi")
  pod_limit     = lookup(var.config, "pod_limit", "20")

  # Resource requests (defaults)
  cpu_request    = lookup(var.config, "cpu_request", "100m")
  memory_request = lookup(var.config, "memory_request", "128Mi")

  # RBAC
  rbac_groups = lookup(var.config, "rbac_groups", [])
  rbac_users  = lookup(var.config, "rbac_users", [])

  # Network policies
  enable_network_policy = lookup(var.config, "enable_network_policy", true)

  # Labels and annotations
  labels      = lookup(var.config, "labels", {})
  annotations = lookup(var.config, "annotations", {})
}

# Get AKS cluster credentials
data "azurerm_kubernetes_cluster" "main" {
  count               = local.cluster_name != "" ? 1 : 0
  name                = local.cluster_name
  resource_group_name = var.resource_group_name
}

# Create namespace
resource "kubernetes_namespace" "main" {
  metadata {
    name = var.name

    labels = merge({
      "managed-by"    = "terraform-self-service"
      "project"       = lookup(var.tags, "Project", "unknown")
      "environment"   = lookup(var.tags, "Environment", "unknown")
      "business-unit" = lookup(var.tags, "BusinessUnit", "unknown")
    }, local.labels)

    annotations = merge({
      "owner" = lookup(var.tags, "Owner", "unknown")
    }, local.annotations)
  }
}

# Resource quota
resource "kubernetes_resource_quota" "main" {
  metadata {
    name      = "${var.name}-quota"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"     = local.cpu_limit
      "requests.memory"  = local.memory_limit
      "limits.cpu"       = local.cpu_limit
      "limits.memory"    = local.memory_limit
      "requests.storage" = local.storage_limit
      "pods"             = local.pod_limit
    }
  }
}

# Limit range for default container resources
resource "kubernetes_limit_range" "main" {
  metadata {
    name      = "${var.name}-limits"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  spec {
    limit {
      type = "Container"

      default = {
        cpu    = "500m"
        memory = "512Mi"
      }

      default_request = {
        cpu    = local.cpu_request
        memory = local.memory_request
      }

      max = {
        cpu    = local.cpu_limit
        memory = local.memory_limit
      }
    }
  }
}

# Network policy - deny all ingress by default (if enabled)
resource "kubernetes_network_policy" "deny_all" {
  count = local.enable_network_policy ? 1 : 0

  metadata {
    name      = "deny-all-ingress"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress"]
  }
}

# RBAC - RoleBinding for groups
resource "kubernetes_role_binding" "groups" {
  for_each = toset(local.rbac_groups)

  metadata {
    name      = "group-${each.value}-binding"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "edit"
  }

  subject {
    kind      = "Group"
    name      = each.value
    api_group = "rbac.authorization.k8s.io"
  }
}

# RBAC - RoleBinding for users
resource "kubernetes_role_binding" "users" {
  for_each = toset(local.rbac_users)

  metadata {
    name      = "user-${replace(each.value, "@", "-at-")}-binding"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "edit"
  }

  subject {
    kind      = "User"
    name      = each.value
    api_group = "rbac.authorization.k8s.io"
  }
}

output "namespace_name" {
  value = kubernetes_namespace.main.metadata[0].name
}

output "namespace_uid" {
  value = kubernetes_namespace.main.metadata[0].uid
}

output "resource_quota" {
  value = {
    cpu     = local.cpu_limit
    memory  = local.memory_limit
    storage = local.storage_limit
    pods    = local.pod_limit
  }
}
