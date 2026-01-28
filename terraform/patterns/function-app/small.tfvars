# Function App - Small T-Shirt Size
# Use case: Development/testing environments
# - Consumption Plan (Y1)
# - Pay-per-execution model
# - Auto-scaling

project       = "myapp"
name          = "api"
business_unit = "engineering"
owners = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# Sizing
sku             = "Y1"  # Consumption Plan
runtime         = "python"
runtime_version = "3.11"
os_type         = "Linux"

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
