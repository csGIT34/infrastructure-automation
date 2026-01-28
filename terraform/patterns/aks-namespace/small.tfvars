# AKS Namespace - Small T-Shirt Size
# Use case: Development/testing environments
# - 2 CPU cores limit
# - 4Gi memory limit
# - 20 pods max

project       = "myapp"
name          = "app"
business_unit = "engineering"
owners        = ["alice@company.com", "bob@company.com"]

# AKS Cluster (existing shared cluster)
aks_cluster_name    = "aks-shared-dev"
aks_resource_group  = "rg-aks-shared"

# Resource Quotas
cpu_limit    = "2"
memory_limit = "4Gi"
pod_limit    = 20

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
