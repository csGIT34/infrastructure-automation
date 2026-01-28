# Function App - Medium T-Shirt Size
# Use case: Pre-production/staging environments
# - Premium Plan (EP1)
# - Always-on with VNet integration
# - Better performance than consumption

project       = "myapp"
name          = "api"
business_unit = "engineering"
owners        = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# Sizing
sku             = "EP1" # Premium Plan: 1 vCore, 3.5GB RAM
runtime         = "python"
runtime_version = "3.11"
os_type         = "Linux"

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
