# Web App (Composite) - Small T-Shirt Size
# Use case: Development/testing environments
# Components: Static Web App + Function App + PostgreSQL + Key Vault
# - Free Static Web App
# - Consumption Function App (Y1)
# - Burstable PostgreSQL (B1ms)

project       = "myapp"
name          = "webapp"
business_unit = "engineering"
owners        = ["alice@company.com", "bob@company.com"]
location      = "eastus"

# Database selection
database_type = "postgresql"  # Options: postgresql, azure_sql, none

# Sizing
swa_sku_tier = "Free"
function_sku = "Y1"                  # Consumption Plan
db_sku       = "B_Standard_B1ms"     # Burstable: 1 vCore

# Function runtime
runtime         = "python"
runtime_version = "3.11"

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
