# Static Web App - Large T-Shirt Size
# Use case: Production environments
# - Standard SKU
# - High bandwidth and multiple custom domains
# - Global CDN distribution

project       = "myapp"
name          = "webapp"
business_unit = "engineering"
owners = ["sa_scottc1@azureskylab.com"]
location      = "eastus2"  # Static Web Apps have specific regions

# Sizing
sku_tier = "Standard"
sku_size = "Standard"

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

# NOTE: Static Web Apps are globally distributed via Azure CDN
# Multi-region HA is built-in - no additional configuration needed
