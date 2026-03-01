# terraform/modules/resource_group/variables.tf

variable "name" {
  description = "Resource group name"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]+$", var.name)) && length(var.name) <= 90
    error_message = "Resource group name must be alphanumeric (with ._-()) and max 90 chars."
  }
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
