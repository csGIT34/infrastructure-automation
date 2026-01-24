# End-to-end tests for the private-endpoint module
#
# Creates a private endpoint connecting to a Key Vault and validates:
# - Private endpoint creation
# - Private IP assignment
# - Network interface creation
# - DNS configuration
#
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

# Generate unique suffix
run "setup" {
  command = apply
  module {
    source = "./setup"
  }
}

# Single comprehensive test
run "private_endpoint_to_keyvault" {
  command = apply

  module {
    source = "./private-endpoint_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Private Endpoint Creation ===
  assert {
    condition     = output.endpoint_id != ""
    error_message = "Private endpoint ID should not be empty"
  }

  assert {
    condition     = can(regex("/privateEndpoints/", output.endpoint_id))
    error_message = "Private endpoint ID should contain /privateEndpoints/ path"
  }

  # === Private IP Assignment ===
  assert {
    condition     = output.endpoint_private_ip != ""
    error_message = "Private endpoint should have a private IP address"
  }

  assert {
    condition     = can(regex("^10\\.0\\.1\\.", output.endpoint_private_ip))
    error_message = "Private IP should be in the 10.0.1.0/24 subnet range"
  }

  # === Network Interface ===
  assert {
    condition     = output.endpoint_network_interface_id != ""
    error_message = "Network interface ID should not be empty"
  }

  assert {
    condition     = can(regex("/networkInterfaces/", output.endpoint_network_interface_id))
    error_message = "Network interface ID should contain /networkInterfaces/ path"
  }

  # === DNS Configuration ===
  assert {
    condition     = length(output.endpoint_custom_dns_configs) > 0
    error_message = "Should have custom DNS configuration"
  }

  # === Resource Group ===
  assert {
    condition     = can(regex("^rg-tftest-pe-", output.resource_group_name))
    error_message = "Resource group should follow naming convention"
  }

  # === Target Resource Connection ===
  assert {
    condition     = output.keyvault_id != ""
    error_message = "Key Vault should be created as target resource"
  }

  assert {
    condition     = output.subnet_id != ""
    error_message = "Subnet should be created for endpoint"
  }
}
