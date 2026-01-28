# Key Vault - Small T-Shirt Size
# Use case: Development/testing environments
# - Standard SKU
# - Basic features enabled
# - Single region

project       = "myapp"
name          = "secrets"
business_unit = "engineering"
owners = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# Sizing
sku = "standard"

# Features (always enabled)
enable_diagnostics      = true
enable_access_review    = true
enable_private_endpoint = true

# Supporting infrastructure
subnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-networking/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-private-endpoints"
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
