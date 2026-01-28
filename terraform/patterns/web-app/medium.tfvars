# Web App (Composite) - Medium T-Shirt Size
# Use case: Pre-production/staging environments
# Components: Static Web App + Function App + PostgreSQL + Key Vault
# - Standard Static Web App
# - Premium Function App (EP1)
# - General Purpose PostgreSQL (D4s_v3)

project       = "myapp"
name          = "webapp"
business_unit = "engineering"
owners        = ["alice@company.com", "bob@company.com"]
location      = "eastus"

# Database selection
database_type = "postgresql"  # Options: postgresql, azure_sql, none

# Sizing
swa_sku_tier = "Standard"
function_sku = "EP1"                 # Premium Plan: 1 vCore
db_sku       = "GP_Standard_D4s_v3"  # General Purpose: 4 vCores

# Function runtime
runtime         = "python"
runtime_version = "3.11"

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
