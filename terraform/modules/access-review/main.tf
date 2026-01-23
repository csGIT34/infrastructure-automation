# terraform/modules/access-review/main.tf
# Access Review configuration placeholder
#
# NOTE: Azure AD Access Reviews cannot be managed via Terraform.
# The azuread provider does not support access review resources.
# Access reviews must be configured manually via:
#   - Azure Portal: Entra ID > Identity Governance > Access Reviews
#   - Microsoft Graph API
#   - PowerShell (Microsoft.Graph module)
#
# This module outputs instructions for manual setup.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
}

variable "group_id" {
  description = "Object ID of the group to review"
  type        = string
}

variable "group_name" {
  description = "Display name of the group (for review naming)"
  type        = string
}

variable "reviewer_emails" {
  description = "Email addresses of reviewers"
  type        = list(string)
}

variable "frequency" {
  description = "Review frequency: quarterly, semi-annual, annual"
  type        = string
  default     = "quarterly"

  validation {
    condition     = contains(["quarterly", "semi-annual", "annual"], var.frequency)
    error_message = "Frequency must be quarterly, semi-annual, or annual."
  }
}

variable "auto_remove_on_deny" {
  description = "Automatically remove access when denied"
  type        = bool
  default     = true
}

variable "duration_days" {
  description = "Number of days for review period"
  type        = number
  default     = 14
}

locals {
  frequency_display = {
    quarterly   = "every 3 months"
    semi-annual = "every 6 months"
    annual      = "every 12 months"
  }
}

output "review_id" {
  description = "Access review definition ID (not created - manual setup required)"
  value       = null
}

output "review_name" {
  description = "Access review display name"
  value       = "Access Review: ${var.group_name}"
}

output "enabled" {
  description = "Whether access review was created (always false - manual setup required)"
  value       = false
}

output "setup_instructions" {
  description = "Instructions for manual access review setup"
  value       = <<-EOT
    Access Review Manual Setup Required
    ====================================
    Azure AD Access Reviews cannot be managed via Terraform.

    To configure access review for group "${var.group_name}":

    1. Go to Azure Portal > Entra ID > Identity Governance > Access Reviews
    2. Click "New access review"
    3. Configure:
       - Review name: Access Review: ${var.group_name}
       - Scope: Groups and Teams > ${var.group_name}
       - Reviewers: ${join(", ", var.reviewer_emails)}
       - Frequency: ${local.frequency_display[var.frequency]}
       - Duration: ${var.duration_days} days
       - Auto-apply results: ${var.auto_remove_on_deny ? "Yes" : "No"}

    Or use PowerShell:
      Install-Module Microsoft.Graph
      Connect-MgGraph -Scopes "AccessReview.ReadWrite.All"
      # See Microsoft Graph documentation for New-MgAccessReview

    Group ID: ${var.group_id}
  EOT
}
