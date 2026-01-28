# Linux VM - Small T-Shirt Size
# Use case: Development/testing environments
# - B1s instance (1 vCPU, 1GB RAM)
# - 30GB Standard HDD
# - Ubuntu 22.04 LTS

project       = "myapp"
name          = "jumpbox"
business_unit = "engineering"
owners = ["sa_scottc1@azureskylab.com"]
location      = "eastus"

# Sizing
vm_size         = "Standard_B1s"  # Burstable: 1 vCPU, 1GB RAM
os_disk_size_gb = 30
os_disk_type    = "Standard_LRS"

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
