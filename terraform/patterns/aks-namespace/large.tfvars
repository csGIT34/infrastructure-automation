# AKS Namespace - Large T-Shirt Size
# Use case: Production environments
# - 8 CPU cores limit
# - 16Gi memory limit
# - 80 pods max

project       = "myapp"
name          = "app"
business_unit = "engineering"
owners        = ["sa_scottc1@azureskylab.com"]

# AKS Cluster (existing shared cluster)
aks_cluster_name   = "aks-shared-prod"
aks_resource_group = "rg-aks-shared"

# Resource Quotas
cpu_limit    = "8"
memory_limit = "16Gi"
pod_limit    = 80

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"

# NOTE: For multi-region HA, deploy namespaces to AKS clusters in multiple regions
# and use Azure Front Door or Traffic Manager for global load balancing
