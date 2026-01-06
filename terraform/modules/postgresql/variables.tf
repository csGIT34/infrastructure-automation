variable "name" {
    type        = string
    description = "Name of the PostgreSQL server"
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
    description = "PostgreSQL configuration"
}

variable "tags" {
    type        = map(string)
    default     = {}
    description = "Resource tags"
}
