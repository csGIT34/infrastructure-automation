# Setup module for linux-vm pattern tests

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
