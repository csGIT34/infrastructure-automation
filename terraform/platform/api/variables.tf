# terraform/platform/api/variables.tf
# Input variables for the Dry Run API infrastructure

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "infra-api"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus2"
}

variable "business_unit" {
  description = "Business unit for tagging"
  type        = string
  default     = "platform"
}

variable "owners" {
  description = "Email addresses of API owners"
  type        = list(string)
  default     = []
}

variable "sku" {
  description = "App Service Plan SKU (Y1 for Consumption, B1/S1 for dedicated)"
  type        = string
  default     = "Y1"
}

variable "cors_allowed_origins" {
  description = "CORS allowed origins for the API"
  type        = list(string)
  default     = ["*"]
}

variable "app_insights_key" {
  description = "Application Insights instrumentation key (optional)"
  type        = string
  default     = ""
}
