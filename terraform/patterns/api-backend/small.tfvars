# API Backend (Composite) - Small T-Shirt Size
# Use case: Development/testing environments
# Components: Function App + Database + Key Vault
# - Flex Consumption Function App (FC1)
# - Basic SQL Database or Burstable PostgreSQL

project       = "myapp"
name          = "api"
business_unit = "engineering"
owners        = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# Database selection
database_type = "azure_sql" # Options: azure_sql, postgresql, mongodb, none

# Sizing
function_sku = "FC1"  # Flex Consumption (no VM quota required)
db_sku       = "Free" # Free tier for SQL, or B_Standard_B1ms for PostgreSQL

# Function runtime
runtime         = "python"
runtime_version = "" # Empty = use module default

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
