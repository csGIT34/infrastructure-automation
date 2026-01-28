# Azure SQL Database - Medium T-Shirt Size
# Use case: Pre-production/staging environments
# - Standard S2 SKU (50 DTUs)
# - 250GB storage
# - Single zone

project       = "myapp"
name          = "appdb"
business_unit = "engineering"
owners        = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# Sizing
sku_name       = "S2"
max_size_gb    = 250
zone_redundant = false

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
