# Storage Account - Large T-Shirt Size
# Use case: Production environments
# - Standard tier
# - Geo-zone-redundant storage (GZRS)
# - Hot access tier
# - Multi-region HA with zone redundancy

project       = "myapp"
name          = "data"
business_unit = "engineering"
owners        = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# Sizing
account_tier     = "Standard"
replication_type = "GZRS" # Geo-Zone-Redundant Storage (3 zones + geo-replication to paired region)
access_tier      = "Hot"

# Containers
containers = ["uploads", "processed", "archives", "backups"]

# Features (always enabled)
enable_diagnostics      = true
enable_access_review    = true
enable_private_endpoint = true

# Supporting infrastructure
subnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-networking/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-private-endpoints"
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"

# NOTE: GZRS provides:
# - Zone redundancy in primary region (eastus - 3 copies across availability zones)
# - Geo-replication to paired region (westus - 3 additional copies)
# - Total: 6 copies of data for maximum durability
