# terraform/patterns/storage_account/variables.tf

variable "project" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be 'dev', 'staging', or 'prod'."
  }
}

variable "name" {
  description = "Resource name suffix"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "business_unit" {
  description = "Business unit for tagging"
  type        = string
  default     = ""
}

variable "owners" {
  description = "List of owner email addresses"
  type        = list(string)

  validation {
    condition     = length(var.owners) > 0
    error_message = "At least one owner email is required."
  }
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
  default     = true
}

variable "soft_delete_days" {
  description = "Soft delete retention days (0 to disable)"
  type        = number
  default     = 7
}

variable "containers" {
  description = "List of blob container names to create"
  type        = list(string)
  default     = []
}

variable "enable_diagnostics" {
  description = "Enable diagnostic settings"
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostics"
  type        = string
  default     = null
}

variable "enable_access_review" {
  description = "Enable access review (typically prod only)"
  type        = bool
  default     = false
}
