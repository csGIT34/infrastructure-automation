# Tests for the naming module
#
# This module generates no Azure resources - it's pure logic.
# Tests validate naming conventions and edge cases.

# Test standard resource naming
run "standard_resource_name" {
  command = plan

  module {
    source = "../../../modules/naming"
  }

  variables {
    project       = "myapp"
    environment   = "dev"
    resource_type = "postgresql"
    name          = "maindb"
  }

  assert {
    condition     = output.name == "psql-myapp-maindb-dev"
    error_message = "Standard name should be 'psql-myapp-maindb-dev', got '${output.name}'"
  }

  assert {
    condition     = output.prefix == "psql"
    error_message = "Prefix should be 'psql'"
  }

  assert {
    condition     = output.resource_group_name == "rg-myapp-dev"
    error_message = "Resource group name should be 'rg-myapp-dev'"
  }
}

# Test storage account naming (no hyphens, max 24 chars)
run "storage_account_name" {
  command = plan

  module {
    source = "../../../modules/naming"
  }

  variables {
    project       = "my-app"
    environment   = "production"
    resource_type = "storage_account"
    name          = "data-store"
  }

  assert {
    condition     = !can(regex("-", output.name))
    error_message = "Storage account name should not contain hyphens"
  }

  assert {
    condition     = length(output.name) <= 24
    error_message = "Storage account name should be max 24 chars, got ${length(output.name)}"
  }

  assert {
    condition     = output.name == lower(output.name)
    error_message = "Storage account name should be lowercase"
  }
}

# Test keyvault naming (max 24 chars)
run "keyvault_name" {
  command = plan

  module {
    source = "../../../modules/naming"
  }

  variables {
    project       = "myapp"
    environment   = "dev"
    resource_type = "keyvault"
    name          = "secrets"
  }

  assert {
    condition     = length(output.name) <= 24
    error_message = "Key Vault name should be max 24 chars, got ${length(output.name)}"
  }

  assert {
    condition     = startswith(output.name, "kv-")
    error_message = "Key Vault name should start with 'kv-'"
  }
}

# Test keyvault with pattern_name for uniqueness
run "keyvault_with_pattern_name" {
  command = plan

  module {
    source = "../../../modules/naming"
  }

  variables {
    project       = "myapp"
    environment   = "dev"
    resource_type = "keyvault"
    name          = "secrets"
    pattern_name  = "webapi"
  }

  # Resource name uses 'name' variable, not pattern_name
  assert {
    condition     = output.name == "kv-myapp-secrets-d"
    error_message = "Key Vault name should be 'kv-myapp-secrets-d', got '${output.name}'"
  }

  # Resource group DOES include pattern_name
  assert {
    condition     = output.resource_group_name == "rg-myapp-webapi-dev"
    error_message = "Resource group should include pattern_name"
  }
}

# Test tags generation
run "tags_generation" {
  command = plan

  module {
    source = "../../../modules/naming"
  }

  variables {
    project       = "myapp"
    environment   = "prod"
    resource_type = "function_app"
    name          = "processor"
    business_unit = "engineering"
  }

  assert {
    condition     = output.tags.Project == "myapp"
    error_message = "Tags should include Project"
  }

  assert {
    condition     = output.tags.Environment == "prod"
    error_message = "Tags should include Environment"
  }

  assert {
    condition     = output.tags.BusinessUnit == "engineering"
    error_message = "Tags should include BusinessUnit"
  }

  assert {
    condition     = output.tags.ManagedBy == "Terraform-Patterns"
    error_message = "Tags should include ManagedBy"
  }
}

# Test long project names get truncated for storage
run "long_name_storage_truncation" {
  command = plan

  module {
    source = "../../../modules/naming"
  }

  variables {
    project       = "verylongprojectname"
    environment   = "development"
    resource_type = "storage_account"
    name          = "primarystorage"
  }

  assert {
    condition     = length(output.name) <= 24
    error_message = "Storage name must be max 24 chars even with long inputs"
  }
}

# Test all resource type prefixes
run "eventhub_prefix" {
  command = plan

  module {
    source = "../../../modules/naming"
  }

  variables {
    project       = "app"
    environment   = "dev"
    resource_type = "eventhub"
    name          = "events"
  }

  assert {
    condition     = output.prefix == "evh"
    error_message = "EventHub prefix should be 'evh'"
  }
}

run "function_app_prefix" {
  command = plan

  module {
    source = "../../../modules/naming"
  }

  variables {
    project       = "app"
    environment   = "dev"
    resource_type = "function_app"
    name          = "api"
  }

  assert {
    condition     = output.prefix == "func"
    error_message = "Function App prefix should be 'func'"
  }
}

run "linux_vm_prefix" {
  command = plan

  module {
    source = "../../../modules/naming"
  }

  variables {
    project       = "app"
    environment   = "dev"
    resource_type = "linux_vm"
    name          = "worker"
  }

  assert {
    condition     = output.prefix == "vm"
    error_message = "Linux VM prefix should be 'vm'"
  }
}
