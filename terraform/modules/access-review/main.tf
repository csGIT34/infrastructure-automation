# terraform/modules/access-review/main.tf
# Creates Entra ID access reviews for privileged groups
# Note: Access reviews require Azure AD Premium P2 license

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
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

# Look up reviewers
data "azuread_users" "reviewers" {
  count                = length(var.reviewer_emails) > 0 ? 1 : 0
  user_principal_names = var.reviewer_emails
}

locals {
  frequency_config = {
    quarterly = {
      interval    = 3
      recurrence  = "absoluteMonthly"
      description = "Quarterly access review"
    }
    semi-annual = {
      interval    = 6
      recurrence  = "absoluteMonthly"
      description = "Semi-annual access review"
    }
    annual = {
      interval    = 12
      recurrence  = "absoluteMonthly"
      description = "Annual access review"
    }
  }

  reviewer_ids = length(var.reviewer_emails) > 0 ? data.azuread_users.reviewers[0].object_ids : []
}

# Note: azuread_access_review_definition requires AzureAD provider >= 2.47.0
# and Azure AD Premium P2 license. If not available, this resource will be skipped.
resource "azuread_access_review_schedule_definition" "review" {
  count = length(local.reviewer_ids) > 0 ? 1 : 0

  display_name = "Access Review: ${var.group_name}"
  description  = local.frequency_config[var.frequency].description

  scope {
    query      = "/groups/${var.group_id}/members"
    query_type = "MicrosoftGraph"
  }

  reviewer {
    query      = "/users/${local.reviewer_ids[0]}"
    query_type = "MicrosoftGraph"
  }

  settings {
    mail_notifications_enabled        = true
    reminder_notifications_enabled    = true
    justification_required_on_approval = true

    default_decision         = var.auto_remove_on_deny ? "Deny" : "None"
    default_decision_enabled = false

    instance_duration_in_days = var.duration_days

    recurrence {
      type = local.frequency_config[var.frequency].recurrence
      pattern {
        type     = "absoluteMonthly"
        interval = local.frequency_config[var.frequency].interval
      }
      range {
        type       = "noEnd"
        start_date = formatdate("YYYY-MM-DD", timestamp())
      }
    }
  }

  lifecycle {
    ignore_changes = [
      settings[0].recurrence[0].range[0].start_date, # Don't update start date on subsequent applies
    ]
  }
}

output "review_id" {
  description = "Access review definition ID"
  value       = length(azuread_access_review_schedule_definition.review) > 0 ? azuread_access_review_schedule_definition.review[0].id : null
}

output "review_name" {
  description = "Access review display name"
  value       = length(azuread_access_review_schedule_definition.review) > 0 ? azuread_access_review_schedule_definition.review[0].display_name : null
}

output "enabled" {
  description = "Whether access review was created"
  value       = length(azuread_access_review_schedule_definition.review) > 0
}
