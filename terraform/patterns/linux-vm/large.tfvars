# Linux VM - Large T-Shirt Size
# Use case: Production environments
# - D4s_v3 instance (4 vCPUs, 16GB RAM)
# - 512GB Premium SSD
# - Ubuntu 22.04 LTS

project       = "myapp"
name          = "prodserver"
business_unit = "engineering"
owners = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# Sizing
vm_size         = "Standard_D4s_v3"  # General Purpose: 4 vCPUs, 16GB RAM
os_disk_size_gb = 512
os_disk_type    = "Premium_LRS"      # Premium SSD for better IOPS

# OS Image
admin_username  = "azureuser"
image_publisher = "Canonical"
image_offer     = "0001-com-ubuntu-server-jammy"
image_sku       = "22_04-lts"

# Features (always enabled)
enable_diagnostics   = true
enable_access_review = true

# Network (required)
subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-networking/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-vms"

# Supporting infrastructure
log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-main"

# NOTE: For multi-region HA, deploy a second VM in DR region (e.g., westus)
# and use Azure Load Balancer or Application Gateway for failover
