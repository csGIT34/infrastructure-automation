# Microservice (Composite) - Large T-Shirt Size
# Use case: Production environments
# Components: AKS Namespace + Event Hub + Storage + Key Vault
# - 8 CPU cores, 16Gi memory
# - Standard Event Hub with higher capacity
# - GZRS storage (geo-redundant)

project       = "myapp"
name          = "orderservice"
business_unit = "engineering"
owners = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# AKS Cluster (existing shared cluster)
aks_cluster_name   = "aks-shared-prod"
aks_resource_group = "rg-aks-shared"

# Sizing
cpu_limit    = "8"
memory_limit = "16Gi"
eventhub_sku = "Standard"

# Features
enable_eventhub      = true
enable_storage       = true
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"

# NOTE: For multi-region HA:
# - Deploy namespaces to AKS clusters in multiple regions
# - Use Azure Front Door or Traffic Manager for global load balancing
# - Event Hub automatically pairs with westus for geo-redundancy (Standard SKU)
