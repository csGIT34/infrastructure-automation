# PostgreSQL - Small T-Shirt Size
# Use case: Development/testing environments
# - Burstable SKU (1-2 vCores)
# - 32GB storage
# - 7-day backup retention
# - Single region

project       = "myapp"
name          = "appdb"
business_unit = "engineering"
owners = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# Sizing
sku                   = "B_Standard_B1ms"  # Burstable: 1 vCore, 2GB RAM
storage_mb            = 32768              # 32GB
version               = "14"
backup_retention_days = 7
geo_redundant_backup  = false              # Single region

# Features (always enabled)
enable_diagnostics      = true
enable_access_review    = true
enable_private_endpoint = true

# Supporting infrastructure
subnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-networking/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-private-endpoints"
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
