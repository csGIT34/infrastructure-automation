# terraform/modules/diagnostic-settings/main.tf
# Configures Azure Monitor diagnostic settings

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

variable "name" {
  description = "Name for the diagnostic setting"
  type        = string
}

variable "target_resource_id" {
  description = "Resource ID to configure diagnostics for"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for logs"
  type        = string
  default     = ""
}

variable "storage_account_id" {
  description = "Storage account ID for archival"
  type        = string
  default     = ""
}

variable "eventhub_authorization_rule_id" {
  description = "Event Hub authorization rule ID for streaming"
  type        = string
  default     = ""
}

variable "eventhub_name" {
  description = "Event Hub name for streaming"
  type        = string
  default     = ""
}

variable "logs" {
  description = "Log categories to enable"
  type        = list(string)
  default     = []
}

variable "metrics" {
  description = "Metric categories to enable"
  type        = list(string)
  default     = ["AllMetrics"]
}

variable "retention_days" {
  description = "Number of days to retain logs (0 = indefinite)"
  type        = number
  default     = 30
}

resource "azurerm_monitor_diagnostic_setting" "settings" {
  name                           = "diag-${var.name}"
  target_resource_id             = var.target_resource_id
  log_analytics_workspace_id     = var.log_analytics_workspace_id != "" ? var.log_analytics_workspace_id : null
  storage_account_id             = var.storage_account_id != "" ? var.storage_account_id : null
  eventhub_authorization_rule_id = var.eventhub_authorization_rule_id != "" ? var.eventhub_authorization_rule_id : null
  eventhub_name                  = var.eventhub_name != "" ? var.eventhub_name : null

  dynamic "enabled_log" {
    for_each = var.logs
    content {
      category = enabled_log.value
    }
  }

  dynamic "metric" {
    for_each = var.metrics
    content {
      category = metric.value
      enabled  = true
    }
  }
}

output "id" {
  description = "Diagnostic setting ID"
  value       = azurerm_monitor_diagnostic_setting.settings.id
}

output "name" {
  description = "Diagnostic setting name"
  value       = azurerm_monitor_diagnostic_setting.settings.name
}
