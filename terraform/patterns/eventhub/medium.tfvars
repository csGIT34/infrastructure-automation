# Event Hub - Medium T-Shirt Size
# Use case: Pre-production/staging environments
# - Standard SKU
# - 2 throughput units
# - 4 partitions
# - 3 days message retention

project       = "myapp"
name          = "events"
business_unit = "engineering"
owners        = ["alice@company.com", "bob@company.com"]
location      = "eastus"

# Sizing
sku               = "Standard"
capacity          = 2
partition_count   = 4
message_retention = 3

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
