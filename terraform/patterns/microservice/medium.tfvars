# Microservice (Composite) - Medium T-Shirt Size
# Use case: Pre-production/staging environments
# Components: AKS Namespace + Event Hub + Storage + Key Vault
# - 4 CPU cores, 8Gi memory
# - Standard Event Hub
# - ZRS storage

project       = "myapp"
name          = "orderservice"
business_unit = "engineering"
owners = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# AKS Cluster (existing shared cluster)
aks_cluster_name   = "aks-shared-staging"
aks_resource_group = "rg-aks-shared"

# Sizing
cpu_limit    = "4"
memory_limit = "8Gi"
eventhub_sku = "Standard"

# Features
enable_eventhub      = true
enable_storage       = true
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
