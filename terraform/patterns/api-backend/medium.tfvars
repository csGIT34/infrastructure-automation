# API Backend (Composite) - Medium T-Shirt Size
# Use case: Pre-production/staging environments
# Components: Function App + Database + Key Vault
# - Premium Function App (EP1)
# - Standard SQL (S2) or General Purpose PostgreSQL

project       = "myapp"
name          = "api"
business_unit = "engineering"
owners        = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# Database selection
database_type = "azure_sql" # Options: azure_sql, postgresql, mongodb, none

# Sizing
function_sku = "EP1" # Premium Plan: 1 vCore
db_sku       = "S2"  # Standard S2 (50 DTUs), or GP_Standard_D4s_v3 for PostgreSQL

# Function runtime
runtime         = "python"
runtime_version = "" # Empty = use module default

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
