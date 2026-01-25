# End-to-end tests for the microservice pattern
#
# Tests Event Hub + Storage + Key Vault + Security Groups + Access Reviews
# Note: AKS namespace is skipped as it requires an existing AKS cluster
# Authentication: Uses ARM_* environment variables

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false # Handled by cleanup script
      recover_soft_deleted_key_vaults = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azuread" {}


# Variables from terraform.tfvars
variables {
  test_owner_email = ""  # Passed via -var-file
}

# Generate unique suffix
run "setup" {
  command = apply
  module {
    source = "./setup"
  }
}

# Deploy Microservice pattern
run "deploy_microservice_pattern" {
  command = apply

  module {
    source = "./microservice_pattern_test"
  }

  variables {
    resource_suffix = run.setup.suffix
    owner_email     = var.test_owner_email
  }

  # === Event Hub ===
  assert {
    condition     = output.eventhub.namespace != ""
    error_message = "Event Hub namespace should not be empty"
  }

  assert {
    condition     = output.eventhub.id != ""
    error_message = "Event Hub namespace ID should not be empty"
  }

  # === Storage Account ===
  assert {
    condition     = output.storage.name != ""
    error_message = "Storage account name should not be empty"
  }

  assert {
    condition     = output.storage.endpoint != ""
    error_message = "Storage account endpoint should not be empty"
  }

  assert {
    condition     = can(regex("^https://.*\\.blob\\.core\\.windows\\.net/$", output.storage.endpoint))
    error_message = "Storage endpoint should be valid Azure blob URL"
  }

  # === Key Vault ===
  assert {
    condition     = output.keyvault.name != ""
    error_message = "Key Vault name should not be empty"
  }

  assert {
    condition     = output.keyvault.uri != ""
    error_message = "Key Vault URI should not be empty"
  }

  assert {
    condition     = can(regex("^https://.*\\.vault\\.azure\\.net/$", output.keyvault.uri))
    error_message = "Key Vault URI should be valid Azure URL"
  }

  # === Security Groups ===
  assert {
    condition     = contains(keys(output.security_groups), "ms-developers")
    error_message = "Should have ms-developers security group"
  }

  assert {
    condition     = contains(keys(output.security_groups), "ms-admins")
    error_message = "Should have ms-admins security group"
  }

  assert {
    condition     = can(regex("^sg-tftest-", output.security_groups["ms-developers"]))
    error_message = "Security group should follow naming convention"
  }

  # === Access Reviews ===
  assert {
    condition     = output.access_reviews.developers != ""
    error_message = "Developers access review should be created"
  }

  assert {
    condition     = output.access_reviews.admins != ""
    error_message = "Admins access review should be created"
  }

  # === Resource Group ===
  assert {
    condition     = can(regex("^rg-tftest-.*-microservice-dev$", output.resource_group))
    error_message = "Resource group should follow naming convention"
  }

  # === Access Info ===
  assert {
    condition     = can(regex("Event Hub:", output.access_info))
    error_message = "Access info should include Event Hub details"
  }

  assert {
    condition     = can(regex("Storage Account:", output.access_info))
    error_message = "Access info should include Storage details"
  }

  assert {
    condition     = can(regex("Key Vault:", output.access_info))
    error_message = "Access info should include Key Vault details"
  }
}
