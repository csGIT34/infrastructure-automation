# terraform/modules/postgresql/variables.tf

variable "name" {
  description = "PostgreSQL server name"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$", var.name))
    error_message = "PostgreSQL server name must be lowercase alphanumeric with hyphens, 3-63 chars."
  }
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "postgresql_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "16"

  validation {
    condition     = contains(["13", "14", "15", "16", "17"], var.postgresql_version)
    error_message = "PostgreSQL version must be one of: 13, 14, 15, 16, 17."
  }
}

variable "admin_username" {
  description = "Administrator username"
  type        = string
  default     = "psqladmin"
}

variable "sku_name" {
  description = "PostgreSQL SKU name (e.g., B_Standard_B1ms, GP_Standard_D2s_v3)"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_mb" {
  description = "Storage size in MB"
  type        = number
  default     = 32768

  validation {
    condition     = var.storage_mb >= 32768
    error_message = "Storage must be at least 32768 MB (32 GB)."
  }
}

variable "backup_retention_days" {
  description = "Backup retention in days"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "Backup retention must be between 7 and 35 days."
  }
}

variable "geo_redundant_backup" {
  description = "Enable geo-redundant backups"
  type        = bool
  default     = false
}

variable "availability_zone" {
  description = "Availability zone"
  type        = string
  default     = null
}

variable "public_network_access_enabled" {
  description = "Enable public network access (set false for VNet-integrated deployments)"
  type        = bool
  default     = false
}

variable "firewall_rules" {
  description = "Map of firewall rule name to {start_ip, end_ip} (only when public access is enabled)"
  type = map(object({
    start_ip = string
    end_ip   = string
  }))
  default = {}
}

variable "database_name" {
  description = "Database name to create"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
