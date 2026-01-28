# Azure SQL Database - Small T-Shirt Size
# Use case: Development/testing environments
# - Basic SKU (5 DTUs)
# - 2GB storage
# - Single zone

project       = "myapp"
name          = "appdb"
business_unit = "engineering"
owners = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# Sizing
sku_name       = "Basic"
max_size_gb    = 2
zone_redundant = false

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
