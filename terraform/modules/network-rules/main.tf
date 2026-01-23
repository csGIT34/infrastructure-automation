# terraform/modules/network-rules/main.tf
# Configures firewall and network access rules for Azure resources
#
# NOTE: Key Vault network rules must be configured on the azurerm_key_vault
# resource itself using the network_acls block, not as a separate resource.
# This module handles Storage, PostgreSQL, and Azure SQL network rules.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

variable "resource_type" {
  description = "Type of resource: storage, postgresql, azure_sql"
  type        = string

  validation {
    condition     = contains(["storage", "postgresql", "azure_sql"], var.resource_type)
    error_message = "Resource type must be storage, postgresql, or azure_sql. Key Vault network rules must be configured on the azurerm_key_vault resource."
  }
}

variable "resource_id" {
  description = "Resource ID to configure network rules for"
  type        = string
}

variable "resource_name" {
  description = "Resource name (for some resource types)"
  type        = string
  default     = ""
}

variable "resource_group_name" {
  description = "Resource group name (for some resource types)"
  type        = string
  default     = ""
}

variable "default_action" {
  description = "Default action for network rules: Allow or Deny"
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Allow", "Deny"], var.default_action)
    error_message = "Default action must be Allow or Deny."
  }
}

variable "allowed_ips" {
  description = "List of IP addresses or CIDR ranges to allow"
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "List of subnet IDs to allow"
  type        = list(string)
  default     = []
}

variable "bypass_azure_services" {
  description = "Allow Azure services to bypass network rules"
  type        = bool
  default     = true
}

# Storage account network rules
resource "azurerm_storage_account_network_rules" "storage" {
  count = var.resource_type == "storage" ? 1 : 0

  storage_account_id         = var.resource_id
  default_action             = var.default_action
  bypass                     = var.bypass_azure_services ? ["AzureServices"] : []
  ip_rules                   = var.allowed_ips
  virtual_network_subnet_ids = var.allowed_subnet_ids
}

# PostgreSQL firewall rules - individual rules per IP
resource "azurerm_postgresql_flexible_server_firewall_rule" "postgresql" {
  for_each = var.resource_type == "postgresql" ? toset(var.allowed_ips) : toset([])

  name             = "allow-${replace(each.value, "/", "-")}"
  server_id        = var.resource_id
  start_ip_address = split("/", each.value)[0]
  end_ip_address   = split("/", each.value)[0]
}

# PostgreSQL allow Azure services
resource "azurerm_postgresql_flexible_server_firewall_rule" "postgresql_azure_services" {
  count = var.resource_type == "postgresql" && var.bypass_azure_services ? 1 : 0

  name             = "AllowAzureServices"
  server_id        = var.resource_id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Azure SQL firewall rules
resource "azurerm_mssql_firewall_rule" "azure_sql" {
  for_each = var.resource_type == "azure_sql" ? toset(var.allowed_ips) : toset([])

  name             = "allow-${replace(each.value, "/", "-")}"
  server_id        = var.resource_id
  start_ip_address = split("/", each.value)[0]
  end_ip_address   = split("/", each.value)[0]
}

# Azure SQL allow Azure services
resource "azurerm_mssql_firewall_rule" "azure_sql_azure_services" {
  count = var.resource_type == "azure_sql" && var.bypass_azure_services ? 1 : 0

  name             = "AllowAzureServices"
  server_id        = var.resource_id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

output "configured" {
  description = "Whether network rules were configured"
  value       = true
}

output "default_action" {
  description = "Default network action"
  value       = var.default_action
}

output "allowed_ips_count" {
  description = "Number of allowed IPs"
  value       = length(var.allowed_ips)
}

output "allowed_subnets_count" {
  description = "Number of allowed subnets"
  value       = length(var.allowed_subnet_ids)
}
