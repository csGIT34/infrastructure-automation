# End-to-end tests for the linux-vm module
#
# Creates a single Linux VM and validates everything.
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
run "linux_vm_with_managed_identity" {
  command = apply

  module {
    source = "./linux-vm_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === VM Creation ===
  assert {
    condition     = output.vm_name != ""
    error_message = "VM name should not be empty"
  }

  assert {
    condition     = output.vm_id != ""
    error_message = "VM ID should not be empty"
  }

  assert {
    condition     = can(regex("^/subscriptions/.*/resourceGroups/.*/providers/Microsoft.Compute/virtualMachines/.*$", output.vm_id))
    error_message = "VM ID should be a valid Azure resource ID"
  }

  # === Network Configuration ===
  assert {
    condition     = output.private_ip_address != ""
    error_message = "Private IP address should not be empty"
  }

  assert {
    condition     = can(regex("^10\\.0\\.1\\.[0-9]+$", output.private_ip_address))
    error_message = "Private IP should be in the 10.0.1.0/24 subnet"
  }

  assert {
    condition     = output.public_ip_address == null
    error_message = "Public IP should be null when public_ip is disabled"
  }

  # === Authentication ===
  assert {
    condition     = output.admin_username == "testadmin"
    error_message = "Admin username should be 'testadmin'"
  }

  assert {
    condition     = output.ssh_private_key != null && output.ssh_private_key != ""
    error_message = "SSH private key should be generated"
  }

  # === Managed Identity ===
  assert {
    condition     = output.principal_id != null && output.principal_id != ""
    error_message = "Managed identity principal ID should not be empty"
  }

  assert {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", output.principal_id))
    error_message = "Principal ID should be a valid GUID"
  }

  # === Resource Group ===
  assert {
    condition     = can(regex("^rg-tftest-linux-vm-", output.resource_group_name))
    error_message = "Resource group should follow naming convention"
  }
}
