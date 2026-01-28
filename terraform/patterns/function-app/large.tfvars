# Function App - Large T-Shirt Size
# Use case: Production environments
# - Premium Plan (EP3)
# - High performance with VNet integration
# - Multi-region deployment example

project       = "myapp"
name          = "api"
business_unit = "engineering"
owners        = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# Sizing
sku             = "EP3" # Premium Plan: 4 vCores, 14GB RAM
runtime         = "python"
runtime_version = "3.11"
os_type         = "Linux"

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"

# NOTE: For multi-region HA, deploy a second Function App in DR region (e.g., westus)
# and use Azure Front Door or Traffic Manager for global load balancing
