terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "config" { type = any }
variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  # VM Size
  size = lookup(var.config, "size", "Standard_B1s")

  # OS Image
  image_publisher = lookup(var.config, "image_publisher", "Canonical")
  image_offer     = lookup(var.config, "image_offer", "0001-com-ubuntu-server-jammy")
  image_sku       = lookup(var.config, "image_sku", "22_04-lts-gen2")
  image_version   = lookup(var.config, "image_version", "latest")

  # Disk
  os_disk_type = lookup(var.config, "os_disk_type", "Standard_LRS")
  os_disk_size = lookup(var.config, "os_disk_size_gb", 30)

  # Data disks
  data_disks = lookup(var.config, "data_disks", [])

  # Networking
  subnet_id          = lookup(var.config, "subnet_id", null)
  public_ip          = lookup(var.config, "public_ip", false)
  private_ip_address = lookup(var.config, "private_ip_address", null)

  # Authentication
  admin_username   = lookup(var.config, "admin_username", "azureuser")
  ssh_public_key   = lookup(var.config, "ssh_public_key", null)
  generate_ssh_key = lookup(var.config, "generate_ssh_key", true)

  # Boot diagnostics
  boot_diagnostics = lookup(var.config, "boot_diagnostics", true)

  # Identity
  identity_type = lookup(var.config, "identity_type", "SystemAssigned")

  # Custom data (cloud-init)
  custom_data = lookup(var.config, "custom_data", null)

  # Availability
  availability_zone = lookup(var.config, "availability_zone", null)
}

# Generate SSH key if not provided
resource "tls_private_key" "ssh" {
  count     = local.generate_ssh_key && local.ssh_public_key == null ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Public IP (optional)
resource "azurerm_public_ip" "main" {
  count               = local.public_ip ? 1 : 0
  name                = "${var.name}-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = local.availability_zone != null ? [local.availability_zone] : null

  tags = var.tags
}

# Network interface
resource "azurerm_network_interface" "main" {
  name                = "${var.name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = local.subnet_id
    private_ip_address_allocation = local.private_ip_address != null ? "Static" : "Dynamic"
    private_ip_address            = local.private_ip_address
    public_ip_address_id          = local.public_ip ? azurerm_public_ip.main[0].id : null
  }

  tags = var.tags
}

# Linux Virtual Machine
resource "azurerm_linux_virtual_machine" "main" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = local.size
  admin_username      = local.admin_username
  zone                = local.availability_zone

  network_interface_ids = [azurerm_network_interface.main.id]

  admin_ssh_key {
    username   = local.admin_username
    public_key = local.ssh_public_key != null ? local.ssh_public_key : tls_private_key.ssh[0].public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = local.os_disk_type
    disk_size_gb         = local.os_disk_size
  }

  source_image_reference {
    publisher = local.image_publisher
    offer     = local.image_offer
    sku       = local.image_sku
    version   = local.image_version
  }

  dynamic "identity" {
    for_each = local.identity_type != "None" ? [1] : []
    content {
      type = local.identity_type
    }
  }

  dynamic "boot_diagnostics" {
    for_each = local.boot_diagnostics ? [1] : []
    content {
      storage_account_uri = null # Use managed storage
    }
  }

  custom_data = local.custom_data != null ? base64encode(local.custom_data) : null

  tags = var.tags
}

# Data disks
resource "azurerm_managed_disk" "data" {
  for_each = { for d in local.data_disks : d.name => d }

  name                 = "${var.name}-${each.value.name}"
  resource_group_name  = var.resource_group_name
  location             = var.location
  storage_account_type = lookup(each.value, "type", "Standard_LRS")
  create_option        = "Empty"
  disk_size_gb         = lookup(each.value, "size_gb", 100)
  zone                 = local.availability_zone

  tags = var.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  for_each = { for d in local.data_disks : d.name => d }

  managed_disk_id    = azurerm_managed_disk.data[each.key].id
  virtual_machine_id = azurerm_linux_virtual_machine.main.id
  lun                = lookup(each.value, "lun", index(local.data_disks, each.value))
  caching            = lookup(each.value, "caching", "ReadWrite")
}

output "vm_id" {
  value = azurerm_linux_virtual_machine.main.id
}

output "vm_name" {
  value = azurerm_linux_virtual_machine.main.name
}

output "private_ip_address" {
  value = azurerm_network_interface.main.private_ip_address
}

output "public_ip_address" {
  value = local.public_ip ? azurerm_public_ip.main[0].ip_address : null
}

output "admin_username" {
  value = local.admin_username
}

output "ssh_private_key" {
  value     = local.generate_ssh_key && local.ssh_public_key == null ? tls_private_key.ssh[0].private_key_pem : null
  sensitive = true
}

output "principal_id" {
  value = local.identity_type != "None" ? azurerm_linux_virtual_machine.main.identity[0].principal_id : null
}
