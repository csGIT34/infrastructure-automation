# terraform/modules/storage_account/variables.tf

variable "name" {
  description = "Storage account name (3-24 chars, lowercase alphanumeric)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "Storage account name must be 3-24 lowercase alphanumeric characters."
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

variable "account_tier" {
  description = "Storage account tier (Standard or Premium)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "Account tier must be 'Standard' or 'Premium'."
  }
}

variable "replication_type" {
  description = "Replication type (LRS, GRS, ZRS, RAGRS)"
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "GRS", "ZRS", "RAGRS", "GZRS", "RAGZRS"], var.replication_type)
    error_message = "Replication type must be one of: LRS, GRS, ZRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "access_tier" {
  description = "Access tier (Hot, Cool)"
  type        = string
  default     = "Hot"

  validation {
    condition     = contains(["Hot", "Cool"], var.access_tier)
    error_message = "Access tier must be 'Hot' or 'Cool'."
  }
}

variable "enable_versioning" {
  description = "Enable blob versioning"
  type        = bool
  default     = false
}

variable "soft_delete_days" {
  description = "Soft delete retention days (0 to disable)"
  type        = number
  default     = 0

  validation {
    condition     = var.soft_delete_days == 0 || (var.soft_delete_days >= 1 && var.soft_delete_days <= 365)
    error_message = "Soft delete days must be 0 (disabled) or between 1 and 365."
  }
}

variable "containers" {
  description = "List of blob container names to create"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
