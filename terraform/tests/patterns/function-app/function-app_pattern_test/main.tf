# Test fixture: Function App pattern
#
# Replicates the function-app pattern composition for testing.

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
  name          = "func"
  business_unit = "engineering"
  pattern_name  = "function-app"
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

# Function App
module "function_naming" {
  source = "../../../../modules/naming"

  project       = local.project
  environment   = local.environment
  resource_type = "function_app"
  name          = local.name
  business_unit = local.business_unit
}

module "function_app" {
  source = "../../../../modules/function-app"

  name                = module.function_naming.name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  config = {
    sku             = "FC1"  # Flex Consumption - no VM quota required
    runtime         = "python"
    runtime_version = "3.11"
    os_type         = "Linux"
    app_settings    = {}
    cors_origins    = ["*"]
  }
  tags = module.naming.tags
}

# Key Vault for secrets
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
  secrets = module.function_app.secrets_for_keyvault
  secrets_user_principal_ids = {
    (local.name) = module.function_app.principal_id
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
      suffix      = "func-developers"
      description = "Developers for ${local.name} function app (test)"
    },
    {
      suffix      = "func-admins"
      description = "Administrators for ${local.name} function app (test)"
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
      principal_id         = module.security_groups.group_ids["func-developers"]
      role_definition_name = "Website Contributor"
      scope                = module.function_app.id
      description          = "Function developers - deploy access (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["func-admins"]
      role_definition_name = "Website Contributor"
      scope                = module.function_app.id
      description          = "Function admins - full access (test)"
    },
    {
      principal_id         = module.security_groups.group_ids["func-admins"]
      role_definition_name = "Key Vault Secrets Officer"
      scope                = module.keyvault.vault_id
      description          = "Function admins - secrets management (test)"
    }
  ]
}

# Access Reviews for Security Groups
module "access_review_developers" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["func-developers"]
  group_name = module.security_groups.group_names["func-developers"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

module "access_review_admins" {
  source = "../../../../modules/access-review"

  group_id   = module.security_groups.group_ids["func-admins"]
  group_name = module.security_groups.group_names["func-admins"]
  frequency  = "annual"
  start_date = formatdate("YYYY-MM-DD", timestamp())
}

# Outputs
output "function_app" {
  value = {
    name         = module.function_app.name
    url          = module.function_app.url
    id           = module.function_app.id
    principal_id = module.function_app.principal_id
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
    developers = module.access_review_developers.review_name
    admins     = module.access_review_admins.review_name
  }
}

output "access_info" {
  value = <<-EOT
    Function App: ${module.function_app.name}
    URL: ${module.function_app.url}

    Key Vault: ${module.keyvault.vault_name}
    URI: ${module.keyvault.vault_uri}
    Managed Identity: ${module.function_app.principal_id}

    Security Groups:
    - Developers: ${module.security_groups.group_names["func-developers"]}
    - Admins: ${module.security_groups.group_names["func-admins"]}

    Access Reviews:
    - ${module.access_review_developers.review_name}
    - ${module.access_review_admins.review_name}

    Deploy with Azure Functions Core Tools:
      func azure functionapp publish ${module.function_app.name}
  EOT
}
