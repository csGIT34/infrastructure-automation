# End-to-end tests for the eventhub module
#
# Creates an Event Hub namespace with hubs, consumer groups, and authorization rules.
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
run "eventhub_namespace_with_hubs" {
  command = apply

  module {
    source = "./eventhub_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Namespace Creation ===
  assert {
    condition     = output.namespace_name != ""
    error_message = "Event Hub namespace name should not be empty"
  }

  assert {
    condition     = can(regex("^evhns-tftest-", output.namespace_name))
    error_message = "Namespace should follow naming convention"
  }

  assert {
    condition     = output.namespace_id != ""
    error_message = "Event Hub namespace ID should not be empty"
  }

  # === Hubs Creation ===
  assert {
    condition     = length(output.hubs) == 2
    error_message = "Should have 2 Event Hubs created"
  }

  assert {
    condition     = contains([for h in output.hubs : h.name], "events")
    error_message = "Should have 'events' hub"
  }

  assert {
    condition     = contains([for h in output.hubs : h.name], "telemetry")
    error_message = "Should have 'telemetry' hub"
  }

  # === Partition Configuration ===
  assert {
    condition     = [for h in output.hubs : h.partition_count if h.name == "telemetry"][0] == 4
    error_message = "Telemetry hub should have 4 partitions"
  }

  # === Resource Group ===
  assert {
    condition     = can(regex("^rg-tftest-eventhub-", output.resource_group_name))
    error_message = "Resource group should follow naming convention"
  }
}
