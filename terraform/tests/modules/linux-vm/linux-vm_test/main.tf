# Test fixture: Linux VM with managed identity
#
# Single consolidated test that validates:
# - VM creation
# - Network interface configuration
# - SSH key generation
# - Managed identity

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
  }
}

variable "resource_suffix" {
  type = string
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "owner_email" {
  description = "Email address of the resource owner for tagging"
  type        = string
  default     = ""
}

locals {
  tags = merge(
    {
      Purpose = "Terraform-Test"
      Module  = "linux-vm"
    },
    var.owner_email != "" ? { Owner = var.owner_email } : {}
  )
}

# Create test resource group
resource "azurerm_resource_group" "test" {
  name     = "rg-tftest-linux-vm-${var.resource_suffix}"
  location = var.location

  tags = local.tags
}

# Create VNet for VM
resource "azurerm_virtual_network" "test" {
  name                = "vnet-tftest-${var.resource_suffix}"
  resource_group_name = azurerm_resource_group.test.name
  location            = azurerm_resource_group.test.location
  address_space       = ["10.0.0.0/16"]

  tags = local.tags
}

# Create subnet for VM
resource "azurerm_subnet" "test" {
  name                 = "snet-tftest-${var.resource_suffix}"
  resource_group_name  = azurerm_resource_group.test.name
  virtual_network_name = azurerm_virtual_network.test.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Test the linux-vm module
module "linux_vm" {
  source = "../../../../modules/linux-vm"

  name                = "vm-tftest-${var.resource_suffix}"
  resource_group_name = azurerm_resource_group.test.name
  location            = azurerm_resource_group.test.location

  config = {
    size             = "Standard_B1s"
    os_disk_size_gb  = 30
    os_disk_type     = "Standard_LRS"
    admin_username   = "testadmin"
    generate_ssh_key = true
    subnet_id        = azurerm_subnet.test.id
    public_ip        = false
    boot_diagnostics = true
    identity_type    = "SystemAssigned"
  }

  tags = local.tags
}

# Outputs for assertions
output "vm_id" {
  value = module.linux_vm.vm_id
}

output "vm_name" {
  value = module.linux_vm.vm_name
}

output "private_ip_address" {
  value = module.linux_vm.private_ip_address
}

output "public_ip_address" {
  value = module.linux_vm.public_ip_address
}

output "admin_username" {
  value = module.linux_vm.admin_username
}

output "principal_id" {
  value = module.linux_vm.principal_id
}

output "ssh_private_key" {
  value     = module.linux_vm.ssh_private_key
  sensitive = true
}

output "resource_group_name" {
  value = azurerm_resource_group.test.name
}

output "subnet_id" {
  value = azurerm_subnet.test.id
}
