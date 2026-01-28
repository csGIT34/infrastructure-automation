# Data Pipeline (Composite) - Large T-Shirt Size
# Use case: Production environments
# Components: Event Hub + Function App + Storage + MongoDB + Key Vault
# - Standard Event Hub (4 TUs, 16 partitions, 7 days retention)
# - Premium Function App (EP3)
# - GZRS Storage (geo-redundant)

project       = "myapp"
name          = "datapipe"
business_unit = "engineering"
owners = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# Sizing
eventhub_sku        = "Standard"
eventhub_capacity   = 4
function_sku        = "EP3"   # Premium Plan: 4 vCores
storage_replication = "GZRS"  # Geo-zone-redundant

# Pipeline configuration
partition_count   = 16
message_retention = 7
runtime           = "python"
enable_mongodb    = true

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"

# NOTE: For multi-region HA:
# - Deploy pipeline components in DR region (e.g., westus)
# - Event Hub Standard SKU includes geo-disaster recovery pairing
# - GZRS storage provides automatic geo-replication
# - Cosmos DB (MongoDB) can be configured for multi-region writes
