# terraform/modules/container_app/variables.tf

variable "name" {
  description = "Container App name"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", var.name))
    error_message = "Container App name must be lowercase alphanumeric with hyphens, 2-32 chars."
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

variable "container_app_environment_id" {
  description = "Existing Container App Environment ID. If null, a new one is created."
  type        = string
  default     = null
}

variable "environment_name" {
  description = "Container App Environment name (required when creating new environment)"
  type        = string
  default     = null
}

variable "revision_mode" {
  description = "Revision mode (Single or Multiple)"
  type        = string
  default     = "Single"

  validation {
    condition     = contains(["Single", "Multiple"], var.revision_mode)
    error_message = "Revision mode must be 'Single' or 'Multiple'."
  }
}

variable "container_name" {
  description = "Container name (defaults to app name)"
  type        = string
  default     = null
}

variable "container_image" {
  description = "Container image (e.g., mcr.microsoft.com/hello-world-k8s-helm:latest)"
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest"
}

variable "cpu" {
  description = "CPU cores (e.g., 0.25, 0.5, 1.0)"
  type        = number
  default     = 0.25

  validation {
    condition     = contains([0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 4.0], var.cpu)
    error_message = "CPU must be one of: 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 4.0."
  }
}

variable "memory" {
  description = "Memory (e.g., 0.5Gi, 1Gi)"
  type        = string
  default     = "0.5Gi"

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?Gi$", var.memory))
    error_message = "Memory must be in Gi format (e.g., 0.5Gi, 1Gi, 2Gi)."
  }
}

variable "min_replicas" {
  description = "Minimum number of replicas"
  type        = number
  default     = 0

  validation {
    condition     = var.min_replicas >= 0 && var.min_replicas <= 300
    error_message = "Min replicas must be between 0 and 300."
  }
}

variable "max_replicas" {
  description = "Maximum number of replicas"
  type        = number
  default     = 1

  validation {
    condition     = var.max_replicas >= 1 && var.max_replicas <= 300
    error_message = "Max replicas must be between 1 and 300."
  }
}

variable "enable_ingress" {
  description = "Enable HTTP ingress"
  type        = bool
  default     = true
}

variable "external_ingress" {
  description = "Allow external (internet) ingress"
  type        = bool
  default     = false
}

variable "target_port" {
  description = "Target port for ingress"
  type        = number
  default     = 80

  validation {
    condition     = var.target_port >= 1 && var.target_port <= 65535
    error_message = "Target port must be between 1 and 65535."
  }
}

variable "enable_managed_identity" {
  description = "Enable system-assigned managed identity"
  type        = bool
  default     = false
}

variable "environment_variables" {
  description = "Environment variables for the container"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
