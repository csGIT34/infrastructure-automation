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

variable "portal_redirect_uris" {
  description = "Redirect URIs for the portal SPA (for Entra auth)"
  type        = list(string)
  default = [
    "https://wonderful-sand-05ab6a20f.4.azurestaticapps.net/",
    "http://localhost:3000/",
    "http://localhost:5500/",
    "http://127.0.0.1:5500/"
  ]
}
