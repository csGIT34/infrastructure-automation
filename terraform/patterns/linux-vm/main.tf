# terraform/patterns/linux-vm/main.tf
# Linux VM Pattern - Azure Virtual Machine with managed identity

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.0" }
    azuread = { source = "hashicorp/azuread", version = "~> 2.0" }
    tls     = { source = "hashicorp/tls", version = "~> 4.0" }
  }
  backend "azurerm" { use_oidc = true }
}

provider "azurerm" {
  features {}
  use_oidc = true
}
provider "azuread" { use_oidc = true }

# Variables
variable "project" { type = string }
variable "environment" { type = string }
variable "name" { type = string }
variable "owners" { type = list(string) }
variable "business_unit" { type = string }
variable "location" {
  type    = string
  default = "eastus"
}

# Sizing-resolved
variable "vm_size" {
  type    = string
  default = "Standard_B1s"
}
variable "os_disk_size_gb" {
  type    = number
  default = 30
}
variable "os_disk_type" {
  type    = string
  default = "Standard_LRS"
}

# Pattern-specific
variable "subnet_id" { type = string }
variable "admin_username" {
  type    = string
  default = "azureuser"
}
variable "image_publisher" {
  type    = string
  default = "Canonical"
}
variable "image_offer" {
  type    = string
  default = "0001-com-ubuntu-server-jammy"
}
variable "image_sku" {
  type    = string
  default = "22_04-lts"
}

variable "enable_diagnostics" {
  type    = bool
  default = false
}
variable "log_analytics_workspace_id" {
  type    = string
  default = ""
}

# Resource Group
module "naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "resource_group"
  name          = var.name
  business_unit = var.business_unit
}

resource "azurerm_resource_group" "main" {
  name     = module.naming.resource_group_name
  location = var.location
  tags     = module.naming.tags
}

# Linux VM (base module)
module "vm_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "linux_vm"
  name          = var.name
  business_unit = var.business_unit
}

module "linux_vm" {
  source = "../../modules/linux-vm"

  name                = module.vm_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    vm_size         = var.vm_size
    os_disk_size_gb = var.os_disk_size_gb
    os_disk_type    = var.os_disk_type
    admin_username  = var.admin_username
    image_publisher = var.image_publisher
    image_offer     = var.image_offer
    image_sku       = var.image_sku
    subnet_id       = var.subnet_id
  }
  tags = module.naming.tags
}

# Key Vault for SSH keys and secrets
module "keyvault_naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "keyvault"
  name          = var.name
  business_unit = var.business_unit
}

module "keyvault" {
  source = "../../modules/keyvault"

  name                = module.keyvault_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = { sku = "standard", rbac_enabled = true }
  secrets = {
    "vm-private-key" = module.linux_vm.ssh_private_key
    "vm-public-ip"   = module.linux_vm.public_ip
  }
  secrets_user_principal_ids = {
    (var.name) = module.linux_vm.principal_id
  }
  tags = module.naming.tags
}

# Security Groups
module "security_groups" {
  source       = "../../modules/security-groups"
  project      = var.project
  environment  = var.environment
  groups = [
    { suffix = "vm-operators", description = "SSH access to ${var.name} VM" },
    { suffix = "vm-admins", description = "Admin access to ${var.name} VM" }
  ]
  owner_emails = var.owners
}

# RBAC
module "rbac" {
  source = "../../modules/rbac-assignments"
  assignments = [
    {
      principal_id         = module.security_groups.group_ids["vm-operators"]
      role_definition_name = "Virtual Machine User Login"
      scope                = module.linux_vm.vm_id
    },
    {
      principal_id         = module.security_groups.group_ids["vm-admins"]
      role_definition_name = "Virtual Machine Administrator Login"
      scope                = module.linux_vm.vm_id
    },
    {
      principal_id         = module.security_groups.group_ids["vm-admins"]
      role_definition_name = "Key Vault Secrets User"
      scope                = module.keyvault.vault_id
    }
  ]
}

# Outputs
output "vm" {
  value = {
    name         = module.linux_vm.vm_name
    public_ip    = module.linux_vm.public_ip
    principal_id = module.linux_vm.principal_id
  }
}
output "keyvault" { value = { name = module.keyvault.vault_name, uri = module.keyvault.vault_uri } }
output "resource_group" { value = azurerm_resource_group.main.name }
output "security_groups" { value = module.security_groups.group_names }
output "access_info" {
  value = <<-EOT
    VM: ${module.linux_vm.vm_name}
    Public IP: ${module.linux_vm.public_ip}

    SSH Key stored in: ${module.keyvault.vault_name}

    To connect:
      az keyvault secret show --vault-name ${module.keyvault.vault_name} --name vm-private-key -o tsv --query value > ~/.ssh/${var.name}.pem
      chmod 600 ~/.ssh/${var.name}.pem
      ssh -i ~/.ssh/${var.name}.pem ${var.admin_username}@${module.linux_vm.public_ip}
  EOT
}
