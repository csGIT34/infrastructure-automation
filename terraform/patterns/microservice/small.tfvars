# Microservice (Composite) - Small T-Shirt Size
# Use case: Development/testing environments
# Components: AKS Namespace + Event Hub + Storage + Key Vault
# - 2 CPU cores, 4Gi memory
# - Basic Event Hub
# - LRS storage

project       = "myapp"
name          = "orderservice"
business_unit = "engineering"
owners = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# AKS Cluster (existing shared cluster)
aks_cluster_name   = "aks-shared-dev"
aks_resource_group = "rg-aks-shared"

# Sizing
cpu_limit    = "2"
memory_limit = "4Gi"
eventhub_sku = "Basic"

# Features
enable_eventhub      = true
enable_storage       = true
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
