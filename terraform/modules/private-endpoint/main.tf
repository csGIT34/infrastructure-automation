# terraform/modules/private-endpoint/main.tf
# Creates private endpoints with DNS zone integration

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

variable "name" {
  description = "Name for the private endpoint"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for the private endpoint"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the private endpoint"
  type        = string
}

variable "target_resource_id" {
  description = "Resource ID of the target resource"
  type        = string
}

variable "subresource_names" {
  description = "Subresource names for the private endpoint (e.g., ['vault'], ['blob'])"
  type        = list(string)
}

variable "dns_zone_id" {
  description = "Private DNS zone ID for auto-registration"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

resource "azurerm_private_endpoint" "endpoint" {
  name                = "pe-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name}"
    private_connection_resource_id = var.target_resource_id
    subresource_names              = var.subresource_names
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.dns_zone_id != "" ? [1] : []
    content {
      name                 = "dns-${var.name}"
      private_dns_zone_ids = [var.dns_zone_id]
    }
  }
}

output "id" {
  description = "Private endpoint ID"
  value       = azurerm_private_endpoint.endpoint.id
}

output "private_ip" {
  description = "Private IP address of the endpoint"
  value       = azurerm_private_endpoint.endpoint.private_service_connection[0].private_ip_address
}

output "network_interface_id" {
  description = "Network interface ID"
  value       = azurerm_private_endpoint.endpoint.network_interface[0].id
}

output "custom_dns_configs" {
  description = "Custom DNS configuration"
  value       = azurerm_private_endpoint.endpoint.custom_dns_configs
}
