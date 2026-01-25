# Test fixture: Eventhub pattern
#
# Replicates the eventhub pattern composition for testing.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    msgraph = {
      source  = "microsoft/msgraph"
      version = "~> 0.2"
    }
  }
}

variable "resource_suffix" {
  type = string
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "owner_email" {
  description = "Owner email for security groups (optional for tests)"
  type        = string
  default     = ""
}


locals {
  project       = "tftest-${var.resource_suffix}"
  environment   = "dev"
  name          = "eh"
  business_unit = "engineering"
  pattern_name  = "eventhub"
}

# Resource Group
module "naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "resource_group"
  name          = local.name
  business_unit = local.business_unit
  pattern_name  = local.pattern_name
}

resource "azurerm_resource_group" "main" {
  name     = module.naming.resource_group_name
  location = var.location
  tags     = module.naming.tags
}

# Event Hub
module "eventhub_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "eventhub"
  name          = local.name
  business_unit = local.business_unit
}

module "eventhub" {
  source = "../../../../modules/eventhub"

  name                = module.eventhub_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku               = "Basic"
    capacity          = 1
    partition_count   = 2
    message_retention = 1
  }
  tags = module.naming.tags
}

# Key Vault
module "keyvault_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "keyvault"
  name          = local.name
  business_unit = local.business_unit
  pattern_name  = local.pattern_name
}

module "keyvault" {
  source = "../../../../modules/keyvault"

  name                = module.keyvault_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku            = "standard"
    rbac_enabled   = true
    default_action = "Allow"
  }
  secrets = {
    "eventhub-connection-string" = module.eventhub.default_connection_string
    "eventhub-namespace"         = module.eventhub.namespace_name
  }
  tags = module.naming.tags
}

# Security Groups
module "security_groups" {
  source = "../../../../modules/security-groups"

  project     = local.project
  environment = local.environment
  groups = [
    {
      suffix      = "eventhub-senders"
      description = "Send events to ${local.name} (test)"
    },
    {
      suffix      = "eventhub-receivers"
      description = "Receive events from ${local.name} (test)"
    }
  ]
  # Only pass owner_emails if owner_email is set, otherwise empty list
  owner_emails = var.owner_email != "" ? [var.owner_email] : []
}

# RBAC Assignments
module "rbac" {
  source = "../../../../modules/rbac-assignments"

  assignments = [
    {
      principal_id         = module.security_groups.group_ids["eventhub-senders"]
      role_definition_name = "Azure Event Hubs Data Sender"
      scope                = module.eventhub.namespace_id
      description          = "Senders - event hub send access (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["eventhub-receivers"]
      role_definition_name = "Azure Event Hubs Data Receiver"
      scope                = module.eventhub.namespace_id
      description          = "Receivers - event hub receive access (test)"
    }
  ]
}

# Access Reviews for Security Groups
module "access_review_senders" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["eventhub-senders"]
  group_name = module.security_groups.group_names["eventhub-senders"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

module "access_review_receivers" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["eventhub-receivers"]
  group_name = module.security_groups.group_names["eventhub-receivers"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

# Outputs
output "eventhub" {
  value = {
    namespace_name = module.eventhub.namespace_name
    namespace_id   = module.eventhub.namespace_id
    hubs           = module.eventhub.hubs
  }
}

output "keyvault" {
  value = {
    name = module.keyvault.vault_name
    uri  = module.keyvault.vault_uri
    id   = module.keyvault.vault_id
  }
}

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "security_groups" {
  value = module.security_groups.group_names
}

output "access_reviews" {
  value = {
    senders   = module.access_review_senders.review_name
    receivers = module.access_review_receivers.review_name
  }
}

output "access_info" {
  value = <<-EOT
    Event Hub Namespace: ${module.eventhub.namespace_name}
    Key Vault: ${module.keyvault.vault_name}
    Key Vault URI: ${module.keyvault.vault_uri}

    Security Groups:
    - Senders: ${module.security_groups.group_names["eventhub-senders"]}
    - Receivers: ${module.security_groups.group_names["eventhub-receivers"]}

    Access Reviews:
    - ${module.access_review_senders.review_name}
    - ${module.access_review_receivers.review_name}
  EOT
}
