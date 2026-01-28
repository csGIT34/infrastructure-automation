# Key Vault - Large T-Shirt Size
# Use case: Production environments
# - Premium SKU (HSM-backed keys)
# - All features enabled
# - Multi-region example (primary + DR region)

project       = "myapp"
name          = "secrets"
business_unit = "engineering"
owners        = ["alice@company.com", "bob@company.com"]
location      = "eastus"

# Sizing
sku = "premium"

# Features (always enabled)
enable_diagnostics      = true
enable_access_review    = true
enable_private_endpoint = true

# Supporting infrastructure
subnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-networking/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-private-endpoints"
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"

# NOTE: For multi-region HA, deploy a second Key Vault in DR region (e.g., westus)
# and use Azure Key Vault's built-in geo-replication for disaster recovery
