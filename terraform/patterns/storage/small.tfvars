# Storage Account - Small T-Shirt Size
# Use case: Development/testing environments
# - Standard tier
# - Locally redundant storage (LRS)
# - Hot access tier
# - Single region

project       = "myapp"
name          = "data"
business_unit = "engineering"
owners        = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# Sizing
account_tier     = "Standard"
replication_type = "LRS" # Locally Redundant Storage (single datacenter)
access_tier      = "Hot"

# Containers
containers = ["uploads", "processed"]

# Features (always enabled)
enable_diagnostics      = true
enable_access_review    = true
enable_private_endpoint = true

# Supporting infrastructure
subnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-networking/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-private-endpoints"
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
