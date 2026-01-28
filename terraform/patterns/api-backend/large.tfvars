# API Backend (Composite) - Large T-Shirt Size
# Use case: Production environments
# Components: Function App + Database + Key Vault
# - Premium Function App (EP3)
# - Premium SQL (P2) or Memory Optimized PostgreSQL with geo-redundant backup

project       = "myapp"
name          = "api"
business_unit = "engineering"
owners = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# Database selection
database_type = "azure_sql"  # Options: azure_sql, postgresql, mongodb, none

# Sizing
function_sku = "EP3"  # Premium Plan: 4 vCores
db_sku       = "P2"   # Premium P2 (250 DTUs), or MO_Standard_E8s_v3 for PostgreSQL

# Function runtime
runtime         = "python"
runtime_version = ""  # Empty = use module default

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"

# NOTE: For multi-region HA:
# - Deploy API backend in DR region (e.g., westus)
# - Use Azure Front Door or API Management for global load balancing
# - Enable Active Geo-Replication for Azure SQL or geo-redundant backup for PostgreSQL
