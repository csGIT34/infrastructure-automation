variable "name" {
    type        = string
    description = "Name of the Azure SQL Server"
}

variable "resource_group_name" {
    type        = string
    description = "Resource group name"
}

variable "location" {
    type        = string
    description = "Azure location"
}

variable "config" {
    type        = any
    description = "Azure SQL configuration"
    default     = {}
}

variable "tags" {
    type        = map(string)
    default     = {}
    description = "Resource tags"
}
