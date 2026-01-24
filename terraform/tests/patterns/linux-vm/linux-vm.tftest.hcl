# End-to-end tests for the linux-vm PATTERN
#
# Tests the full pattern composition (VM + Key Vault + Security Groups + RBAC + Access Reviews).
# Authentication: Uses ARM_* environment variables

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azuread" {}

run "setup" {
  command = apply
  module {
    source = "./setup"
  }
}

run "deploy_linux_vm_pattern" {
  command = apply

  module {
    source = "./linux-vm_pattern_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Virtual Machine ===
  assert {
    condition     = output.vm.name != ""
    error_message = "VM name should not be empty"
  }

  assert {
    condition     = output.vm.public_ip != null && output.vm.public_ip != ""
    error_message = "VM should have a public IP address"
  }

  assert {
    condition     = output.vm.principal_id != null && output.vm.principal_id != ""
    error_message = "VM should have a managed identity principal ID"
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

  # === Resource Group ===
  assert {
    condition     = output.resource_group != ""
    error_message = "Resource group should not be empty"
  }

  assert {
    condition     = can(regex("^rg-tftest-", output.resource_group))
    error_message = "Resource group should follow naming convention"
  }

  # === Security Groups ===
  assert {
    condition     = contains(keys(output.security_groups), "vm-operators")
    error_message = "Should have 'vm-operators' security group"
  }

  assert {
    condition     = contains(keys(output.security_groups), "vm-admins")
    error_message = "Should have 'vm-admins' security group"
  }

  assert {
    condition     = can(regex("^sg-tftest-", output.security_groups["vm-operators"]))
    error_message = "Security group should follow naming convention"
  }

  # === Access Reviews ===
  assert {
    condition     = output.access_reviews.operators != ""
    error_message = "Operators access review should be created"
  }

  assert {
    condition     = output.access_reviews.admins != ""
    error_message = "Admins access review should be created"
  }

  # === Access Info ===
  assert {
    condition     = can(regex("VM:", output.access_info))
    error_message = "Access info should include VM details"
  }

  assert {
    condition     = can(regex("Key Vault:", output.access_info))
    error_message = "Access info should include Key Vault details"
  }

  assert {
    condition     = can(regex("To connect:", output.access_info))
    error_message = "Access info should include connection instructions"
  }
}
