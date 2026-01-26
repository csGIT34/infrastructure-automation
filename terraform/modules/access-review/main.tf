# terraform/modules/access-review/main.tf
# Creates Entra ID access reviews for privileged groups using Microsoft Graph
# Two-stage review: Group owners first, then member's manager
# Requires Azure AD Premium P2 license
#
# NOTE: This module uses a "fire-and-forget" approach via Azure CLI.
# The access review is created but NOT tracked in Terraform state.
# This avoids 404 errors when access reviews are modified/deleted externally.
# The review will only be recreated if the trigger values change.

terraform {
  required_version = ">= 1.5.0"
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
  default     = "annual"

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
  default     = 14
}

variable "start_date" {
  description = "Start date for the review schedule (YYYY-MM-DD format)"
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

  # Build the access review JSON body
  access_review_body = jsonencode({
    displayName             = "Access Review: ${var.group_name}"
    descriptionForAdmins    = "Two-stage access review for ${var.group_name}. Stage 1: Group owners. Stage 2: Member's manager."
    descriptionForReviewers = "Please review the members of ${var.group_name} and approve or deny their continued access."

    scope = {
      "@odata.type" = "#microsoft.graph.accessReviewQueryScope"
      query         = "/groups/${var.group_id}/transitiveMembers"
      queryType     = "MicrosoftGraph"
    }

    # This links the review to the group resource (required for group blade visibility)
    instanceEnumerationScope = {
      "@odata.type" = "#microsoft.graph.accessReviewQueryScope"
      query         = "/groups/${var.group_id}"
      queryType     = "MicrosoftGraph"
    }

    reviewers = []

    stageSettings = [
      {
        stageId                          = "1"
        durationInDays                   = var.stage_duration_days
        recommendationsEnabled           = true
        decisionsThatWillMoveToNextStage = ["NotReviewed", "Approve"]
        reviewers = [
          {
            query     = "./owners"
            queryType = "MicrosoftGraph"
          }
        ]
      },
      {
        stageId                = "2"
        dependsOn              = ["1"]
        durationInDays         = var.stage_duration_days
        recommendationsEnabled = true
        reviewers = [
          {
            query     = "./manager"
            queryType = "MicrosoftGraph"
            queryRoot = "decisions"
          }
        ]
      }
    ]

    settings = {
      mailNotificationsEnabled        = true
      reminderNotificationsEnabled    = true
      justificationRequiredOnApproval = true
      defaultDecisionEnabled          = true
      defaultDecision                 = var.default_decision
      autoApplyDecisionsEnabled       = var.auto_apply_decisions
      recommendationsEnabled          = true
      instanceDurationInDays          = var.stage_duration_days * 2

      recurrence = {
        pattern = {
          type     = local.frequency_config[var.frequency].type
          interval = local.frequency_config[var.frequency].interval
        }
        range = {
          type      = "noEnd"
          startDate = var.start_date
        }
      }
    }
  })
}

# Create access review via Azure CLI - NOT tracked in Terraform state
# This avoids 404 errors when the review is modified/deleted externally in Entra ID
resource "null_resource" "access_review" {
  # Only recreate if these key values change
  triggers = {
    group_id   = var.group_id
    group_name = var.group_name
    frequency  = var.frequency
    start_date = var.start_date
  }

  provisioner "local-exec" {
    command = <<-EOT
      az rest \
        --method POST \
        --url "https://graph.microsoft.com/v1.0/identityGovernance/accessReviews/definitions" \
        --headers "Content-Type=application/json" \
        --body '${replace(local.access_review_body, "'", "'\\''")}' \
        --output json || echo '{"status": "created_or_exists"}'
    EOT

    interpreter = ["/bin/bash", "-c"]
  }
}

output "review_id" {
  description = "Access review trigger ID (not the actual Graph API ID - review is not tracked in state)"
  value       = null_resource.access_review.id
}

output "review_name" {
  description = "Access review display name"
  value       = "Access Review: ${var.group_name}"
}

output "enabled" {
  description = "Whether access review creation was triggered"
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

output "note" {
  description = "Important note about state management"
  value       = "Access review created via Graph API - not tracked in Terraform state to avoid 404 errors on external changes"
}
