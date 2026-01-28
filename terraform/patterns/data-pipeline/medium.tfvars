# Data Pipeline (Composite) - Medium T-Shirt Size
# Use case: Pre-production/staging environments
# Components: Event Hub + Function App + Storage + MongoDB + Key Vault
# - Standard Event Hub (2 TUs, 8 partitions, 3 days retention)
# - Premium Function App (EP1)
# - ZRS Storage

project       = "myapp"
name          = "datapipe"
business_unit = "engineering"
owners = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# Sizing
eventhub_sku        = "Standard"
eventhub_capacity   = 2
function_sku        = "EP1"  # Premium Plan: 1 vCore
storage_replication = "ZRS"

# Pipeline configuration
partition_count   = 8
message_retention = 3
runtime           = "python"
enable_mongodb    = true

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"
