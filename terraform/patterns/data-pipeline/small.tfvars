# Data Pipeline (Composite) - Small T-Shirt Size
# Use case: Development/testing environments
# Components: Event Hub + Function App + Storage + MongoDB + Key Vault
# - Basic Event Hub (1 TU, 4 partitions, 1 day retention)
# - Consumption Function App (Y1)
# - LRS Storage

project       = "myapp"
name          = "datapipe"
business_unit = "engineering"
owners        = ["alice@company.com", "bob@company.com"]
location      = "eastus"

# Sizing
eventhub_sku      = "Basic"
eventhub_capacity = 1
function_sku      = "Y1"    # Consumption Plan
storage_replication = "LRS"

# Pipeline configuration
partition_count   = 4
message_retention = 1
runtime           = "python"
enable_mongodb    = true

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
