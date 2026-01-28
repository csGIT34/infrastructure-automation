# Event Hub - Large T-Shirt Size
# Use case: Production environments
# - Standard SKU
# - 4 throughput units
# - 8 partitions (more parallelism)
# - 7 days message retention

project       = "myapp"
name          = "events"
business_unit = "engineering"
owners        = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# Sizing
sku               = "Standard"
capacity          = 4
partition_count   = 8
message_retention = 7

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"

# NOTE: For multi-region HA, deploy a second Event Hub namespace in DR region (e.g., westus)
# and configure Event Hub Geo-Disaster Recovery pairing
