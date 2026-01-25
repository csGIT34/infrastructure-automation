# Minimal configuration for terraform test
# The naming module has no providers - it's pure logic

terraform {
  required_version = ">= 1.6.0"
}

# Reference the module so terraform init can find it
module "naming" {
  source = "../../../modules/naming"

  project       = "test"
  environment   = "dev"
  resource_type = "postgresql"
  name          = "test"
}
