# Static Web App - Small T-Shirt Size
# Use case: Development/testing environments
# - Free SKU
# - Limited bandwidth and custom domains

project       = "myapp"
name          = "webapp"
business_unit = "engineering"
owners        = ["sa_scottc1@azureskylab.com"]
location      = "eastus2" # Static Web Apps have specific regions

# Sizing
sku_tier = "Free"
sku_size = "Free"

# Build configuration (example for React app)
repository_url  = ""
branch          = "main"
app_location    = "/"
api_location    = ""
output_location = "build"

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
