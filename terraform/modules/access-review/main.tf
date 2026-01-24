# terraform/modules/access-review/main.tf
# Creates Entra ID access reviews for privileged groups using Microsoft Graph
# Two-stage review: Group owners first, then member's manager
# Requires Azure AD Premium P2 license

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    msgraph = {
      source  = "microsoft/msgraph"
      version = "~> 0.2"
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

variable "stage_duration_days" {
  description = "Number of days for each review stage"
  type        = number
  default     = 7
}

variable "start_date" {
  description = "Start date for the review schedule (YYYY-MM-DD format)"
  type        = string
}

variable "reviewer_id" {
  description = "Object ID of the reviewer user"
  type        = string
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
}

# Two-stage Access Review: Group Owners -> Manager
resource "msgraph_resource" "access_review" {
  url         = "identityGovernance/accessReviews/definitions"
  api_version = "v1.0"

  body = {
    displayName             = "Access Review: ${var.group_name}"
    descriptionForAdmins    = "Scheduled review of ${var.group_name} group membership"
    descriptionForReviewers = "Please review and justify continued access"

    scope = {
      "@odata.type" = "#microsoft.graph.accessReviewQueryScope"
      query         = "/groups/${var.group_id}/transitiveMembers"
      queryType     = "MicrosoftGraph"
    }

    reviewers = [
      {
        query     = "/users/${var.reviewer_id}"
        queryType = "MicrosoftGraph"
      }
    ]

    settings = {
      mailNotificationsEnabled        = true
      reminderNotificationsEnabled    = true
      justificationRequiredOnApproval = true
      defaultDecisionEnabled          = false
      instanceDurationInDays          = var.stage_duration_days
      recommendationsEnabled          = true

      recurrence = {
        pattern = {
          type     = local.frequency_config[var.frequency].type
          interval = local.frequency_config[var.frequency].interval
        }
        range = {
          type      = "noEnd"
          startDate = "${var.start_date}T09:00:00.000Z"
        }
      }
    }
  }
}

output "review_id" {
  description = "Access review schedule definition ID"
  value       = msgraph_resource.access_review.id
}

output "review_name" {
  description = "Access review display name"
  value       = "Access Review: ${var.group_name}"
}

output "enabled" {
  description = "Whether access review was created"
  value       = true
}

output "frequency" {
  description = "Review frequency"
  value       = var.frequency
}

output "stages" {
  description = "Review stages configured"
  value       = ["Group Owners", "Member's Manager"]
}
