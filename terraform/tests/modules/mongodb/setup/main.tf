# Setup module for mongodb tests
# Generates unique suffix for resource names

terraform {
  required_version = ">= 1.6.0"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

output "suffix" {
  value = random_string.suffix.result
}
