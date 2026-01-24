# Test fixture: AKS Namespace with resource quotas and limits
#
# Single consolidated test that validates:
# - Kubernetes namespace creation
# - Resource quota configuration
# - Limit range configuration
# - Network policy creation
#
# Prerequisites:
# - Kubernetes provider must be configured (via KUBE_CONFIG_PATH or provider env vars)
# - The cluster must be accessible from the test runner

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
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
  type        = string
  description = "Email address of the namespace owner"
}

# Local variables for test configuration
locals {
  namespace_name = "tftest-ns-${var.resource_suffix}"
  test_tags = {
    Purpose      = "Terraform-Test"
    Module       = "aks-namespace"
    Project      = "tftest"
    Environment  = "dev"
    BusinessUnit = "engineering"
    Owner        = var.owner_email
  }
}

# Test the aks-namespace module with resource quotas
module "aks_namespace" {
  source = "../../../../modules/aks-namespace"

  name                = local.namespace_name
  resource_group_name = "rg-tftest-${var.resource_suffix}" # Not used when cluster_name not provided
  location            = var.location

  config = {
    # Resource quotas
    cpu_limit     = "4"
    memory_limit  = "8Gi"
    storage_limit = "20Gi"
    pod_limit     = "50"

    # Resource requests
    cpu_request    = "200m"
    memory_request = "256Mi"

    # Network policy
    enable_network_policy = true

    # Custom labels and annotations
    labels = {
      "app.kubernetes.io/managed-by" = "terraform-test"
      "test-run"                     = var.resource_suffix
    }
    annotations = {
      "description" = "Test namespace for aks-namespace module"
    }
  }

  tags = local.test_tags
}

# Outputs for assertions
output "namespace_name" {
  value = module.aks_namespace.namespace_name
}

output "namespace_uid" {
  value = module.aks_namespace.namespace_uid
}

output "resource_quota" {
  value = module.aks_namespace.resource_quota
}

output "expected_cpu_limit" {
  value = "4"
}

output "expected_memory_limit" {
  value = "8Gi"
}

output "expected_storage_limit" {
  value = "20Gi"
}

output "expected_pod_limit" {
  value = "50"
}
