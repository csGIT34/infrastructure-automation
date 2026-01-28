# Storage Account - Medium T-Shirt Size
# Use case: Pre-production/staging environments
# - Standard tier
# - Zone-redundant storage (ZRS)
# - Hot access tier
# - Single region with zone redundancy

project       = "myapp"
name          = "data"
business_unit = "engineering"
owners        = ["alice@company.com", "bob@company.com"]
location      = "eastus"

# Sizing
account_tier     = "Standard"
replication_type = "ZRS"  # Zone-Redundant Storage (3 availability zones)
access_tier      = "Hot"

# Containers
containers = ["uploads", "processed", "archives"]

# Features (always enabled)
enable_diagnostics      = true
enable_access_review    = true
enable_private_endpoint = true

# Supporting infrastructure
subnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-networking/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-private-endpoints"
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
