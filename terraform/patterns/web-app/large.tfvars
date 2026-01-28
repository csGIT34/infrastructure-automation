# Web App (Composite) - Large T-Shirt Size
# Use case: Production environments
# Components: Static Web App + Function App + PostgreSQL + Key Vault
# - Standard Static Web App
# - Premium Function App (EP3)
# - Memory Optimized PostgreSQL (E8s_v3) with geo-redundant backup

project       = "myapp"
name          = "webapp"
business_unit = "engineering"
owners        = ["alice@company.com", "bob@company.com"]
location      = "eastus"

# Database selection
database_type = "postgresql"  # Options: postgresql, azure_sql, none

# Sizing
swa_sku_tier = "Standard"
function_sku = "EP3"                 # Premium Plan: 4 vCores
db_sku       = "MO_Standard_E8s_v3"  # Memory Optimized: 8 vCores

# Function runtime
runtime         = "python"
runtime_version = "3.11"

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"

# NOTE: For multi-region HA:
# - Deploy web app components in DR region (e.g., westus)
# - Use Azure Front Door for global load balancing
# - Enable geo-redundant backup for PostgreSQL
