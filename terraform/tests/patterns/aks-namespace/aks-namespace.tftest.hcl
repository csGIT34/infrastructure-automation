# End-to-end tests for the aks-namespace pattern
#
# Tests Security Groups + Access Reviews for AKS namespace RBAC
# Note: Kubernetes namespace is mocked since it requires a live AKS cluster.
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

provider "msgraph" {}

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

# Deploy AKS Namespace pattern components
run "deploy_aks_namespace_pattern" {
  command = apply

  module {
    source = "./aks-namespace_pattern_test"
  }

  variables {
    resource_suffix = run.setup.suffix
    owner_email     = var.test_owner_email
  }

  # === Namespace (mock) ===
  assert {
    condition     = output.namespace.name != ""
    error_message = "Namespace name should not be empty"
  }

  assert {
    condition     = output.namespace.cluster != ""
    error_message = "Cluster name should not be empty"
  }

  assert {
    condition     = output.namespace.cpu_limit == "2"
    error_message = "CPU limit should be set to default value"
  }

  assert {
    condition     = output.namespace.memory_limit == "4Gi"
    error_message = "Memory limit should be set to default value"
  }

  assert {
    condition     = output.namespace.pod_limit == 20
    error_message = "Pod limit should be set to default value"
  }

  # === Security Groups ===
  assert {
    condition     = contains(keys(output.security_groups), "k8s-viewers")
    error_message = "Should have 'k8s-viewers' security group"
  }

  assert {
    condition     = contains(keys(output.security_groups), "k8s-editors")
    error_message = "Should have 'k8s-editors' security group"
  }

  assert {
    condition     = contains(keys(output.security_groups), "k8s-admins")
    error_message = "Should have 'k8s-admins' security group"
  }

  assert {
    condition     = can(regex("^sg-tftest-", output.security_groups["k8s-viewers"]))
    error_message = "Security group should follow naming convention"
  }

  assert {
    condition     = can(regex("^sg-tftest-", output.security_groups["k8s-editors"]))
    error_message = "Security group should follow naming convention"
  }

  assert {
    condition     = can(regex("^sg-tftest-", output.security_groups["k8s-admins"]))
    error_message = "Security group should follow naming convention"
  }

  # === Access Reviews ===
  assert {
    condition     = output.access_reviews.viewers != ""
    error_message = "Viewers access review should be created"
  }

  assert {
    condition     = output.access_reviews.editors != ""
    error_message = "Editors access review should be created"
  }

  assert {
    condition     = output.access_reviews.admins != ""
    error_message = "Admins access review should be created"
  }

  # === Access Info ===
  assert {
    condition     = can(regex("AKS Namespace Pattern", output.access_info))
    error_message = "Access info should include pattern details"
  }

  assert {
    condition     = can(regex("Security Groups:", output.access_info))
    error_message = "Access info should include security group details"
  }

  assert {
    condition     = can(regex("Access Reviews:", output.access_info))
    error_message = "Access info should include access review details"
  }
}
