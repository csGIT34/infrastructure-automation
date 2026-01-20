terraform {
    required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = "~> 3.0"
        }
    }
}

# -----------------------------------------------------------------------------
# Key Vault Module
# -----------------------------------------------------------------------------
# Creates a Key Vault with RBAC authorization and optional secret storage.
# Supports granting Secrets User access to managed identities.
# -----------------------------------------------------------------------------

variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "config" { type = any }
variable "tags" {
    type    = map(string)
    default = {}
}

# Secrets to store in the vault (name => value)
variable "secrets" {
    description = "Map of secret names to values to store in the vault"
    type        = map(string)
    default     = {}
    sensitive   = true
}

# Principal IDs (managed identities) to grant Secrets User access
variable "secrets_user_principal_ids" {
    description = "Map of resource names to principal IDs for Key Vault Secrets User role"
    type        = map(string)
    default     = {}
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
    name                       = var.name
    resource_group_name        = var.resource_group_name
    location                   = var.location
    tenant_id                  = data.azurerm_client_config.current.tenant_id
    sku_name                   = lookup(var.config, "sku", "standard")
    soft_delete_retention_days = lookup(var.config, "soft_delete_days", 7)
    purge_protection_enabled   = lookup(var.config, "purge_protection", false)

    enable_rbac_authorization = lookup(var.config, "rbac_enabled", true)

    network_acls {
        default_action = lookup(var.config, "default_action", "Allow")
        bypass         = "AzureServices"
    }

    tags = var.tags
}

# -----------------------------------------------------------------------------
# Store secrets in the vault
# -----------------------------------------------------------------------------

resource "azurerm_key_vault_secret" "secrets" {
    # Use nonsensitive() on keys only - values remain sensitive
    # This is required because for_each can't use sensitive values directly
    for_each = nonsensitive(toset(keys(var.secrets)))

    name         = each.key
    value        = var.secrets[each.key]
    key_vault_id = azurerm_key_vault.main.id

    # Ensure Terraform has access before creating secrets
    depends_on = [azurerm_role_assignment.terraform_secrets_officer]
}

# Grant Terraform service principal Secrets Officer to manage secrets
resource "azurerm_role_assignment" "terraform_secrets_officer" {
    scope                = azurerm_key_vault.main.id
    role_definition_name = "Key Vault Secrets Officer"
    principal_id         = data.azurerm_client_config.current.object_id
}

# -----------------------------------------------------------------------------
# Grant Secrets User access to managed identities
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "secrets_user" {
    # Use map keys (static resource names) for for_each, values are principal IDs
    for_each = var.secrets_user_principal_ids

    scope                = azurerm_key_vault.main.id
    role_definition_name = "Key Vault Secrets User"
    principal_id         = each.value
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "vault_uri" { value = azurerm_key_vault.main.vault_uri }
output "vault_id" { value = azurerm_key_vault.main.id }
output "vault_name" { value = azurerm_key_vault.main.name }

output "secret_uris" {
    description = "Map of secret names to their Key Vault URIs"
    value = {
        for name, secret in azurerm_key_vault_secret.secrets :
        name => secret.id
    }
}
