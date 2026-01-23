# terraform/modules/access-review/main.tf
# Creates Entra ID access reviews for privileged groups using Microsoft Graph
# Requires Azure AD Premium P2 license

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    msgraph = {
      source  = "microsoft/msgraph"
      version = "~> 0.2"
    }
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

variable "reviewer_object_ids" {
  description = "Object IDs of reviewers (users or groups)"
  type        = list(string)
  default     = []
}

variable "reviewer_emails" {
  description = "Email addresses of reviewers (alternative to object IDs)"
  type        = list(string)
  default     = []
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

variable "auto_apply_decisions" {
  description = "Automatically apply decisions when review ends"
  type        = bool
  default     = true
}

variable "default_decision" {
  description = "Default decision if reviewer doesn't respond: Approve, Deny, Recommendation"
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Approve", "Deny", "Recommendation"], var.default_decision)
    error_message = "Default decision must be Approve, Deny, or Recommendation."
  }
}

variable "duration_days" {
  description = "Number of days for review period"
  type        = number
  default     = 14
}

variable "start_date" {
  description = "Start date for the review schedule (YYYY-MM-DD format). Defaults to today."
  type        = string
  default     = ""
}

# Look up reviewers by email if provided
data "azuread_users" "reviewers" {
  count                = length(var.reviewer_emails) > 0 ? 1 : 0
  user_principal_names = var.reviewer_emails
}

locals {
  frequency_config = {
    quarterly = {
      interval = 3
      type     = "absoluteMonthly"
    }
    semi-annual = {
      interval = 6
      type     = "absoluteMonthly"
    }
    annual = {
      interval = 12
      type     = "absoluteMonthly"
    }
  }

  # Use provided object IDs or look up from emails
  reviewer_ids = length(var.reviewer_object_ids) > 0 ? var.reviewer_object_ids : (
    length(var.reviewer_emails) > 0 ? data.azuread_users.reviewers[0].object_ids : []
  )

  # Use provided start date or default to today
  start_date = var.start_date != "" ? var.start_date : formatdate("YYYY-MM-DD", timestamp())

  # Build reviewers array for Graph API
  reviewers = [for id in local.reviewer_ids : {
    query     = "/users/${id}"
    queryType = "MicrosoftGraph"
  }]
}

# Access Review Schedule Definition via Microsoft Graph
resource "msgraph_resource" "access_review" {
  count = length(local.reviewer_ids) > 0 ? 1 : 0

  url = "/identityGovernance/accessReviews/definitions"

  body = jsonencode({
    displayName = "Access Review: ${var.group_name}"
    descriptionForAdmins = "Periodic access review for ${var.group_name} group membership"
    descriptionForReviewers = "Please review the members of ${var.group_name} and approve or deny their continued access."

    scope = {
      "@odata.type" = "#microsoft.graph.accessReviewQueryScope"
      query         = "/groups/${var.group_id}/members"
      queryType     = "MicrosoftGraph"
    }

    reviewers = local.reviewers

    settings = {
      mailNotificationsEnabled        = true
      reminderNotificationsEnabled    = true
      justificationRequiredOnApproval = true
      defaultDecisionEnabled          = true
      defaultDecision                 = var.default_decision
      autoApplyDecisionsEnabled       = var.auto_apply_decisions
      recommendationsEnabled          = true
      instanceDurationInDays          = var.duration_days

      recurrence = {
        pattern = {
          type     = local.frequency_config[var.frequency].type
          interval = local.frequency_config[var.frequency].interval
        }
        range = {
          type      = "noEnd"
          startDate = local.start_date
        }
      }
    }
  })

  lifecycle {
    ignore_changes = [
      # Don't update start date on subsequent applies
      body,
    ]
  }
}

output "review_id" {
  description = "Access review schedule definition ID"
  value       = length(msgraph_resource.access_review) > 0 ? msgraph_resource.access_review[0].id : null
}

output "review_name" {
  description = "Access review display name"
  value       = "Access Review: ${var.group_name}"
}

output "enabled" {
  description = "Whether access review was created"
  value       = length(msgraph_resource.access_review) > 0
}

output "frequency" {
  description = "Review frequency"
  value       = var.frequency
}

output "reviewer_count" {
  description = "Number of reviewers configured"
  value       = length(local.reviewer_ids)
}
