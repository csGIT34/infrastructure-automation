# End-to-end tests for the data-pipeline pattern
#
# Tests Event Hub + Function App + Storage + Key Vault + Security Groups + Access Reviews
# Authentication: Uses ARM_* environment variables (source setup/.env)

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false  # Handled by cleanup script
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

# Deploy Data Pipeline pattern
run "deploy_data_pipeline_pattern" {
  command = apply

  module {
    source = "./data-pipeline_pattern_test"
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
    condition     = length(output.eventhub.hubs) > 0
    error_message = "Event Hub should have at least one hub"
  }

  # === Function App (Processor) ===
  assert {
    condition     = output.processor.name != ""
    error_message = "Function App name should not be empty"
  }

  assert {
    condition     = output.processor.url != ""
    error_message = "Function App URL should not be empty"
  }

  assert {
    condition     = output.processor.principal_id != ""
    error_message = "Function App should have managed identity"
  }

  # === Data Lake Storage ===
  assert {
    condition     = output.datalake.name != ""
    error_message = "Data Lake storage account name should not be empty"
  }

  assert {
    condition     = output.datalake.endpoint != ""
    error_message = "Data Lake DFS endpoint should not be empty"
  }

  assert {
    condition     = contains(output.datalake.containers, "raw")
    error_message = "Data Lake should have 'raw' container"
  }

  assert {
    condition     = contains(output.datalake.containers, "processed")
    error_message = "Data Lake should have 'processed' container"
  }

  assert {
    condition     = contains(output.datalake.containers, "errors")
    error_message = "Data Lake should have 'errors' container"
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
    condition     = contains(keys(output.security_groups), "pipeline-developers")
    error_message = "Should have pipeline-developers security group"
  }

  assert {
    condition     = contains(keys(output.security_groups), "pipeline-admins")
    error_message = "Should have pipeline-admins security group"
  }

  assert {
    condition     = contains(keys(output.security_groups), "data-analysts")
    error_message = "Should have data-analysts security group"
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

  assert {
    condition     = output.access_reviews.analysts != ""
    error_message = "Analysts access review should be created"
  }

  # === Resource Group ===
  assert {
    condition     = can(regex("^rg-tftest-.*-data-pipeline-dev$", output.resource_group))
    error_message = "Resource group should follow naming convention"
  }

  # === Access Info ===
  assert {
    condition     = can(regex("Event Hub", output.access_info))
    error_message = "Access info should include Event Hub details"
  }

  assert {
    condition     = can(regex("Function App", output.access_info))
    error_message = "Access info should include Function App details"
  }

  assert {
    condition     = can(regex("Data Lake", output.access_info))
    error_message = "Access info should include Data Lake details"
  }

  assert {
    condition     = can(regex("Key Vault", output.access_info))
    error_message = "Access info should include Key Vault details"
  }
}
