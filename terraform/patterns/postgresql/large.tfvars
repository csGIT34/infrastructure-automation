# PostgreSQL - Large T-Shirt Size
# Use case: Production environments
# - Memory Optimized SKU (8 vCores)
# - 512GB storage
# - 35-day backup retention
# - Geo-redundant backup (multi-region HA)

project       = "myapp"
name          = "appdb"
business_unit = "engineering"
owners        = ["alice@company.com", "bob@company.com"]
location      = "eastus"

# Sizing
sku                   = "MO_Standard_E8s_v3"  # Memory Optimized: 8 vCores, 64GB RAM
storage_mb            = 524288                # 512GB
version               = "14"
backup_retention_days = 35
geo_redundant_backup  = true                  # Multi-region HA (automatic failover to paired region)

# Features (always enabled)
enable_diagnostics      = true
enable_access_review    = true
enable_private_endpoint = true

# Supporting infrastructure
subnet_id                  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-networking/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-private-endpoints"
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"

# NOTE: geo_redundant_backup=true enables automatic replication to Azure paired region
# For eastus, backups replicate to westus automatically
