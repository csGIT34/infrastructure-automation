# Test fixture: AKS Namespace pattern
#
# Tests Security Groups + RBAC structure + Access Reviews
# Note: Kubernetes namespace creation is mocked since it requires a live AKS cluster.
# This test validates the pattern's Azure AD and RBAC components.

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
  name          = "ns"
  business_unit = "engineering"
  pattern_name  = "aks-namespace"

  # Mock values for namespace (would come from actual AKS in production)
  mock_namespace_name = "${local.project}-${local.environment}-${local.name}"
  mock_cluster_name   = "aks-shared-dev"
  mock_cluster_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aks/providers/Microsoft.ContainerService/managedClusters/${local.mock_cluster_name}"

  # Resource quota config
  cpu_limit    = "2"
  memory_limit = "4Gi"
  pod_limit    = 20
}

# Naming module
module "naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "aks_namespace"
  name          = local.name
  business_unit = local.business_unit
  pattern_name  = local.pattern_name
}

# Security Groups (same as pattern)
module "security_groups" {
  source = "../../../../modules/security-groups"

  project     = local.project
  environment = local.environment
  groups = [
    { suffix = "k8s-viewers", description = "View access to ${local.name} namespace (test)" },
    { suffix = "k8s-editors", description = "Edit access to ${local.name} namespace (test)" },
    { suffix = "k8s-admins", description = "Admin access to ${local.name} namespace (test)" }
  ]
  # Only pass owner_emails if owner_email is set, otherwise empty list
  owner_emails = var.owner_email != "" ? [var.owner_email] : []
}

# Access Reviews for Security Groups
module "access_review_viewers" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["k8s-viewers"]
  group_name = module.security_groups.group_names["k8s-viewers"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

module "access_review_editors" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["k8s-editors"]
  group_name = module.security_groups.group_names["k8s-editors"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

module "access_review_admins" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["k8s-admins"]
  group_name = module.security_groups.group_names["k8s-admins"]
  frequency  = "quarterly"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

# Outputs
output "namespace" {
  description = "Mock namespace details (actual namespace requires live AKS cluster)"
  value = {
    name         = local.mock_namespace_name
    cluster      = local.mock_cluster_name
    cpu_limit    = local.cpu_limit
    memory_limit = local.memory_limit
    pod_limit    = local.pod_limit
  }
}

output "security_groups" {
  value = module.security_groups.group_names
}

output "security_group_ids" {
  value = module.security_groups.group_ids
}

output "access_reviews" {
  value = {
    viewers = module.access_review_viewers.review_name
    editors = module.access_review_editors.review_name
    admins  = module.access_review_admins.review_name
  }
}

output "access_info" {
  value = <<-EOT
    AKS Namespace Pattern Test Results
    ===================================

    Namespace (mock): ${local.mock_namespace_name}
    Cluster (mock): ${local.mock_cluster_name}

    Resource Quotas:
    - CPU: ${local.cpu_limit}
    - Memory: ${local.memory_limit}
    - Pods: ${local.pod_limit}

    Security Groups:
    - Viewers: ${module.security_groups.group_names["k8s-viewers"]}
    - Editors: ${module.security_groups.group_names["k8s-editors"]}
    - Admins: ${module.security_groups.group_names["k8s-admins"]}

    Access Reviews:
    - ${module.access_review_viewers.review_name}
    - ${module.access_review_editors.review_name}
    - ${module.access_review_admins.review_name}

    Note: Kubernetes namespace not created - requires live AKS cluster.
    To access a real namespace:
      az aks get-credentials --resource-group rg-aks --name ${local.mock_cluster_name}
      kubectl config set-context --current --namespace=${local.mock_namespace_name}
  EOT
}
