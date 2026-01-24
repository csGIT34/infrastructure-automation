# Common test variables
#
# These are passed to all tests via -var-file

variable "test_subscription_id" {
  description = "Azure subscription ID for running tests"
  type        = string
}

variable "test_tenant_id" {
  description = "Azure tenant ID"
  type        = string
}

variable "test_location" {
  description = "Azure region for test resources"
  type        = string
  default     = "eastus2"
}

variable "test_owner_email" {
  description = "Email address for owner assignments in tests"
  type        = string
}

variable "test_owner_object_id" {
  description = "Object ID of the test owner user (optional, looked up if not provided)"
  type        = string
  default     = ""
}

variable "test_log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostic tests (optional)"
  type        = string
  default     = ""
}

# Test naming prefix - all test resources use this
variable "test_prefix" {
  description = "Prefix for test resource names"
  type        = string
  default     = "tftest"
}
