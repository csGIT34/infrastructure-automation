# PostgreSQL - Medium T-Shirt Size
# Use case: Pre-production/staging environments
# - General Purpose SKU (4 vCores)
# - 128GB storage
# - 14-day backup retention
# - Single region

project       = "myapp"
name          = "appdb"
business_unit = "engineering"
owners        = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# Sizing
sku                   = "GP_Standard_D4s_v3" # General Purpose: 4 vCores, 16GB RAM
storage_mb            = 131072               # 128GB
version               = "14"
backup_retention_days = 14
geo_redundant_backup  = false # Single region

# Features (always enabled)
enable_diagnostics      = true
enable_access_review    = true
enable_private_endpoint = true

# Supporting infrastructure
subnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-networking/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-private-endpoints"
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
