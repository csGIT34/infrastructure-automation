# MongoDB (Cosmos DB) - Large T-Shirt Size
# Use case: Production environments
# - 4,000 RU/s minimum throughput
# - 40,000 RU/s max with autoscale
# - Strong consistency
# - Multi-region with automatic failover

project       = "myapp"
name          = "docdb"
business_unit = "engineering"
owners        = ["alice@company.com", "bob@company.com"]
location      = "eastus"

# Sizing
throughput                = 4000
max_throughput            = 40000
enable_automatic_failover = true   # Multi-region automatic failover
consistency_level         = "Strong"

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"

# NOTE: enable_automatic_failover=true enables multi-region write and automatic failover
# Cosmos DB automatically replicates to paired region (westus for eastus)
