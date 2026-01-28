# AKS Namespace - Medium T-Shirt Size
# Use case: Pre-production/staging environments
# - 4 CPU cores limit
# - 8Gi memory limit
# - 40 pods max

project       = "myapp"
name          = "app"
business_unit = "engineering"
owners        = ["sa_scottc1@azureskylab.com"]

# AKS Cluster (existing shared cluster)
aks_cluster_name   = "aks-shared-staging"
aks_resource_group = "rg-aks-shared"

# Resource Quotas
cpu_limit    = "4"
memory_limit = "8Gi"
pod_limit    = 40

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
