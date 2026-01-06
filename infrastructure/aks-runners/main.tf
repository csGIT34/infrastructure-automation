# =============================================================================
# AKS RUNNERS - PRODUCTION ONLY
# =============================================================================
# This configuration deploys AKS for GitHub runners in production.
# Estimated cost: $200-500+/month depending on node pool scaling
#
# FOR DEVELOPMENT/TESTING: Use local k3s cluster instead (FREE)
# See: infrastructure/local-runners/ and docs/LOCAL-K8S-SETUP.md
#
# To deploy this, you must explicitly run:
#   cd infrastructure/aks-runners && terraform init && terraform apply
# =============================================================================

terraform {
    required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = "~> 3.0"
        }
        kubernetes = {
            source  = "hashicorp/kubernetes"
            version = "~> 2.0"
        }
        helm = {
            source  = "hashicorp/helm"
            version = "~> 2.0"
        }
        random = {
            source  = "hashicorp/random"
            version = "~> 3.0"
        }
    }
}

provider "azurerm" {
    features {}
}

variable "location" {
    type    = string
    default = "eastus"
}

resource "azurerm_resource_group" "runners" {
    name     = "rg-github-runners"
    location = var.location

    tags = {
        Purpose   = "GitHub Self-Hosted Runners"
        ManagedBy = "Terraform"
    }
}

resource "azurerm_virtual_network" "runners" {
    name                = "vnet-github-runners"
    location            = azurerm_resource_group.runners.location
    resource_group_name = azurerm_resource_group.runners.name
    address_space       = ["10.100.0.0/16"]

    tags = azurerm_resource_group.runners.tags
}

resource "azurerm_subnet" "aks" {
    name                 = "snet-aks"
    resource_group_name  = azurerm_resource_group.runners.name
    virtual_network_name = azurerm_virtual_network.runners.name
    address_prefixes     = ["10.100.0.0/20"]
}

resource "azurerm_log_analytics_workspace" "runners" {
    name                = "law-github-runners"
    location            = azurerm_resource_group.runners.location
    resource_group_name = azurerm_resource_group.runners.name
    sku                 = "PerGB2018"
    retention_in_days   = 30

    tags = azurerm_resource_group.runners.tags
}

resource "azurerm_kubernetes_cluster" "runners" {
    name                = "aks-github-runners"
    location            = azurerm_resource_group.runners.location
    resource_group_name = azurerm_resource_group.runners.name
    dns_prefix          = "aks-runners"

    default_node_pool {
        name                 = "system"
        node_count           = 2
        vm_size              = "Standard_D4s_v3"
        vnet_subnet_id       = azurerm_subnet.aks.id
        enable_auto_scaling  = true
        min_count            = 2
        max_count            = 5

        node_labels = {
            "workload" = "system"
        }
    }

    identity {
        type = "SystemAssigned"
    }

    network_profile {
        network_plugin    = "azure"
        load_balancer_sku = "standard"
        outbound_type     = "loadBalancer"
    }

    oms_agent {
        log_analytics_workspace_id = azurerm_log_analytics_workspace.runners.id
    }

    tags = azurerm_resource_group.runners.tags
}

resource "azurerm_kubernetes_cluster_node_pool" "finance" {
    name                  = "finance"
    kubernetes_cluster_id = azurerm_kubernetes_cluster.runners.id
    vm_size               = "Standard_D8s_v3"
    node_count            = 1
    enable_auto_scaling   = true
    min_count             = 1
    max_count             = 20

    node_labels = {
        "business-unit" = "finance"
        "workload"      = "github-runner"
    }

    node_taints = [
        "business-unit=finance:NoSchedule"
    ]

    tags = {
        BusinessUnit = "Finance"
    }
}

resource "azurerm_kubernetes_cluster_node_pool" "marketing" {
    name                  = "marketing"
    kubernetes_cluster_id = azurerm_kubernetes_cluster.runners.id
    vm_size               = "Standard_D8s_v3"
    node_count            = 1
    enable_auto_scaling   = true
    min_count             = 1
    max_count             = 20

    node_labels = {
        "business-unit" = "marketing"
        "workload"      = "github-runner"
    }

    node_taints = [
        "business-unit=marketing:NoSchedule"
    ]

    tags = {
        BusinessUnit = "Marketing"
    }
}

resource "azurerm_kubernetes_cluster_node_pool" "engineering" {
    name                  = "engineering"
    kubernetes_cluster_id = azurerm_kubernetes_cluster.runners.id
    vm_size               = "Standard_D8s_v3"
    node_count            = 1
    enable_auto_scaling   = true
    min_count             = 1
    max_count             = 20

    node_labels = {
        "business-unit" = "engineering"
        "workload"      = "github-runner"
    }

    node_taints = [
        "business-unit=engineering:NoSchedule"
    ]

    tags = {
        BusinessUnit = "Engineering"
    }
}

resource "azurerm_container_registry" "runners" {
    name                = "acrrunners${random_string.suffix.result}"
    resource_group_name = azurerm_resource_group.runners.name
    location            = azurerm_resource_group.runners.location
    sku                 = "Premium"
    admin_enabled       = false

    georeplications {
        location = "westus2"
        tags     = {}
    }

    tags = azurerm_resource_group.runners.tags
}

resource "azurerm_role_assignment" "aks_acr" {
    principal_id                     = azurerm_kubernetes_cluster.runners.kubelet_identity[0].object_id
    role_definition_name             = "AcrPull"
    scope                            = azurerm_container_registry.runners.id
    skip_service_principal_aad_check = true
}

resource "random_string" "suffix" {
    length  = 8
    special = false
    upper   = false
}

output "aks_cluster_name" {
    value = azurerm_kubernetes_cluster.runners.name
}

output "aks_cluster_id" {
    value = azurerm_kubernetes_cluster.runners.id
}

output "acr_login_server" {
    value = azurerm_container_registry.runners.login_server
}

output "resource_group_name" {
    value = azurerm_resource_group.runners.name
}
