# Test fixture: Linux VM pattern
#
# Replicates the linux-vm pattern composition for testing.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    msgraph = {
      source  = "microsoft/msgraph"
      version = "~> 0.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
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
  description = "Owner email for security groups"
  type        = string
}

locals {
  project       = "tftest-${var.resource_suffix}"
  environment   = "dev"
  name          = "vm"
  business_unit = "engineering"
  pattern_name  = "linux-vm"
}

# Resource Group
module "naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "resource_group"
  name          = local.name
  business_unit = local.business_unit
  pattern_name  = local.pattern_name
}

resource "azurerm_resource_group" "main" {
  name     = module.naming.resource_group_name
  location = var.location
  tags     = module.naming.tags
}

# Virtual Network for the VM
resource "azurerm_virtual_network" "main" {
  name                = "${local.project}-${local.environment}-vnet"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.0.0.0/16"]
  tags                = module.naming.tags
}

resource "azurerm_subnet" "main" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Linux VM
module "vm_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "linux_vm"
  name          = local.name
  business_unit = local.business_unit
}

module "linux_vm" {
  source = "../../../../modules/linux-vm"

  name                = module.vm_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    vm_size         = "Standard_B1s"
    os_disk_size_gb = 30
    os_disk_type    = "Standard_LRS"
    admin_username  = "azureuser"
    image_publisher = "Canonical"
    image_offer     = "0001-com-ubuntu-server-jammy"
    image_sku       = "22_04-lts-gen2"
    subnet_id       = azurerm_subnet.main.id
    public_ip       = true
  }
  tags = module.naming.tags
}

# Key Vault for SSH keys and secrets
module "keyvault_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "keyvault"
  name          = local.name
  business_unit = local.business_unit
  pattern_name  = local.pattern_name
}

module "keyvault" {
  source = "../../../../modules/keyvault"

  name                = module.keyvault_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku            = "standard"
    rbac_enabled   = true
    default_action = "Allow"
  }
  secrets = {
    "vm-private-key" = module.linux_vm.ssh_private_key
    "vm-public-ip"   = module.linux_vm.public_ip_address
  }
  secrets_user_principal_ids = {
    (local.name) = module.linux_vm.principal_id
  }
  tags = module.naming.tags
}

# Security Groups
module "security_groups" {
  source = "../../../../modules/security-groups"

  project     = local.project
  environment = local.environment
  groups = [
    {
      suffix      = "vm-operators"
      description = "SSH access to ${local.name} VM (test)"
    },
    {
      suffix      = "vm-admins"
      description = "Admin access to ${local.name} VM (test)"
    }
  ]
  owner_emails = [var.owner_email]
}

# RBAC Assignments
module "rbac" {
  source = "../../../../modules/rbac-assignments"

  assignments = [
    {
      principal_id         = module.security_groups.group_ids["vm-operators"]
      role_definition_name = "Virtual Machine User Login"
      scope                = module.linux_vm.vm_id
      description          = "Operators - VM user login (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["vm-admins"]
      role_definition_name = "Virtual Machine Administrator Login"
      scope                = module.linux_vm.vm_id
      description          = "Admins - VM admin login (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["vm-admins"]
      role_definition_name = "Key Vault Secrets User"
      scope                = module.keyvault.vault_id
      description          = "Admins - Key Vault secrets access (test)"
    }
  ]
}

# Access Reviews for Security Groups
module "access_review_operators" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["vm-operators"]
  group_name = module.security_groups.group_names["vm-operators"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

module "access_review_admins" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["vm-admins"]
  group_name = module.security_groups.group_names["vm-admins"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

# Outputs
output "vm" {
  value = {
    name         = module.linux_vm.vm_name
    public_ip    = module.linux_vm.public_ip_address
    principal_id = module.linux_vm.principal_id
  }
}

output "keyvault" {
  value = {
    name = module.keyvault.vault_name
    uri  = module.keyvault.vault_uri
    id   = module.keyvault.vault_id
  }
}

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "security_groups" {
  value = module.security_groups.group_names
}

output "access_reviews" {
  value = {
    operators = module.access_review_operators.review_name
    admins    = module.access_review_admins.review_name
  }
}

output "access_info" {
  value = <<-EOT
    VM: ${module.linux_vm.vm_name}
    Public IP: ${module.linux_vm.public_ip_address}

    Key Vault: ${module.keyvault.vault_name}
    URI: ${module.keyvault.vault_uri}

    Security Groups:
    - Operators: ${module.security_groups.group_names["vm-operators"]}
    - Admins: ${module.security_groups.group_names["vm-admins"]}

    Access Reviews:
    - ${module.access_review_operators.review_name}
    - ${module.access_review_admins.review_name}

    To connect:
      az keyvault secret show --vault-name ${module.keyvault.vault_name} --name vm-private-key -o tsv --query value > ~/.ssh/${local.name}.pem
      chmod 600 ~/.ssh/${local.name}.pem
      ssh -i ~/.ssh/${local.name}.pem azureuser@${module.linux_vm.public_ip_address}
  EOT
}
