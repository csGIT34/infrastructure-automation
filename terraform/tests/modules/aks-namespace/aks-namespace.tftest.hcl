# End-to-end tests for the aks-namespace module
#
# Creates a Kubernetes namespace with resource quotas, limit ranges,
# and network policies, then validates the configuration.
#
# Prerequisites:
# - Kubernetes cluster must be accessible
# - Set KUBE_CONFIG_PATH or configure kubernetes provider env vars
# - Set TF_VAR_owner_email for the owner email variable
#
# Authentication:
# - Uses KUBE_CONFIG_PATH or kubernetes provider environment variables
# - Uses ARM_* environment variables for Azure (if accessing AKS)

variables {
  owner_email = "test@example.com"
}

provider "kubernetes" {
  # Configuration via environment:
  # - KUBE_CONFIG_PATH for kubeconfig file
  # - Or KUBE_HOST, KUBE_TOKEN, etc. for direct config
}

# Generate unique suffix
run "setup" {
  command = apply
  module {
    source = "./setup"
  }
}

# Single comprehensive namespace test
run "aks_namespace_with_quotas" {
  command = apply

  module {
    source = "./aks-namespace_test"
  }

  variables {
    resource_suffix = run.setup.suffix
  }

  # === Namespace Creation ===
  assert {
    condition     = output.namespace_name != ""
    error_message = "Namespace name should not be empty"
  }

  assert {
    condition     = can(regex("^tftest-ns-", output.namespace_name))
    error_message = "Namespace name should follow naming convention: tftest-ns-{suffix}"
  }

  assert {
    condition     = output.namespace_uid != ""
    error_message = "Namespace UID should not be empty"
  }

  # === Resource Quota Configuration ===
  assert {
    condition     = output.resource_quota.cpu == output.expected_cpu_limit
    error_message = "CPU limit should match configured value"
  }

  assert {
    condition     = output.resource_quota.memory == output.expected_memory_limit
    error_message = "Memory limit should match configured value"
  }

  assert {
    condition     = output.resource_quota.storage == output.expected_storage_limit
    error_message = "Storage limit should match configured value"
  }

  assert {
    condition     = output.resource_quota.pods == output.expected_pod_limit
    error_message = "Pod limit should match configured value"
  }
}
