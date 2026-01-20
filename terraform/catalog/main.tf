terraform {
    required_version = ">= 1.5.0"
    required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = "~> 3.0"
        }
        azuread = {
            source  = "hashicorp/azuread"
            version = "~> 2.0"
        }
        random = {
            source  = "hashicorp/random"
            version = "~> 3.0"
        }
    }

    backend "azurerm" {
        use_oidc = true
    }
}

provider "azurerm" {
    features {
        resource_group {
            prevent_deletion_if_contains_resources = false
        }
        key_vault {
            purge_soft_delete_on_destroy = true
        }
    }
    use_oidc = true
}

provider "azuread" {
    use_oidc = true
}

variable "config_file" {
    description = "Path to YAML configuration file"
    type        = string
}

locals {
    config    = yamldecode(file(var.config_file))
    metadata  = local.config.metadata
    resources = local.config.resources

    # Owner emails for RBAC - supports both single owner_email and owners array
    owner_emails = distinct(concat(
        lookup(local.metadata, "owners", []),
        lookup(local.metadata, "owner_email", "") != "" ? [local.metadata.owner_email] : []
    ))

    # Check if RBAC should be enabled (requires at least one owner)
    enable_rbac = length(local.owner_emails) > 0

    common_tags = merge(
        {
            Project       = local.metadata.project_name
            Environment   = local.metadata.environment
            BusinessUnit  = local.metadata.business_unit
            CostCenter    = local.metadata.cost_center
            Owner         = join(",", local.owner_emails)
            ManagedBy     = "Terraform-SelfService"
        },
        lookup(local.metadata, "tags", {})
    )

    resource_group_name = "rg-${local.metadata.project_name}-${local.metadata.environment}"
    location            = lookup(local.metadata, "location", "eastus")

    # Project Key Vault name (auto-created for secrets)
    project_keyvault_name = "kv-${local.metadata.project_name}-${local.metadata.environment}"

    # Use resource name as key (stable) instead of index (shifts when resources removed)
    postgresql_resources    = { for r in local.resources : r.name => r if r.type == "postgresql" }
    mongodb_resources       = { for r in local.resources : r.name => r if r.type == "mongodb" }
    keyvault_resources      = { for r in local.resources : r.name => r if r.type == "keyvault" }
    aks_namespace_resources = { for r in local.resources : r.name => r if r.type == "aks_namespace" }
    eventhub_resources      = { for r in local.resources : r.name => r if r.type == "eventhub" }
    function_resources      = { for r in local.resources : r.name => r if r.type == "function_app" }
    vm_resources            = { for r in local.resources : r.name => r if r.type == "linux_vm" }
    storage_resources        = { for r in local.resources : r.name => r if r.type == "storage_account" }
    static_web_app_resources = { for r in local.resources : r.name => r if r.type == "static_web_app" }
    azure_sql_resources      = { for r in local.resources : r.name => r if r.type == "azure_sql" }

    # Collect all managed identity principal IDs (for Key Vault access)
    # Use a map with static keys (resource names) so for_each works at plan time
    all_principal_ids = merge(
        { for k, v in module.function_app : "function-${k}" => v.principal_id },
        { for k, v in module.azure_sql : "sql-${k}" => v.principal_id },
        { for k, v in module.linux_vm : "vm-${k}" => v.principal_id }
    )

    # Collect all secrets from modules for Key Vault storage
    all_secrets = merge(
        # SQL secrets
        merge([for k, v in module.azure_sql : v.secrets_for_keyvault]...),
        # Function App secrets
        merge([for k, v in module.function_app : v.secrets_for_keyvault]...)
    )
}

resource "azurerm_resource_group" "main" {
    name     = local.resource_group_name
    location = local.location
    tags     = local.common_tags
}

# -----------------------------------------------------------------------------
# Project Key Vault (auto-created for secrets storage)
# -----------------------------------------------------------------------------
# Every project gets a Key Vault to store generated secrets (SQL passwords,
# connection strings, etc.). Managed identities get Secrets User access.

module "project_keyvault" {
    source = "../modules/keyvault"

    name                = local.project_keyvault_name
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = {
        sku              = "standard"
        soft_delete_days = 7
        purge_protection = false
        rbac_enabled     = true
    }
    tags = local.common_tags

    # Store all collected secrets from resource modules
    secrets = local.all_secrets

    # Grant Secrets User to all managed identities
    secrets_user_principal_ids = local.all_principal_ids
}

# -----------------------------------------------------------------------------
# Project RBAC (Entra ID Security Groups)
# -----------------------------------------------------------------------------
# Creates security groups for owners with delegated administration.
# Owners can manage group membership after creation.

module "project_rbac" {
    source = "../modules/project-rbac"
    count  = local.enable_rbac ? 1 : 0

    project_name      = local.metadata.project_name
    environment       = local.metadata.environment
    owner_emails      = local.owner_emails
    resource_group_id = azurerm_resource_group.main.id
    keyvault_id       = module.project_keyvault.vault_id
    tags              = local.common_tags

    # Pass resource IDs for RBAC assignments
    # Deployable resources (deployers group)
    function_app_ids   = { for k, v in module.function_app : k => v.id }
    static_web_app_ids = { for k, v in module.static_web_app : k => v.id }
    # Note: AKS namespaces are Kubernetes resources, not Azure ARM resources
    # RBAC for AKS is typically at cluster level, not namespace level
    aks_namespace_ids = {}

    # Data resources (data group)
    sql_server_ids         = { for k, v in module.azure_sql : k => v.server_id }
    postgresql_server_ids  = { for k, v in module.postgresql : k => v.server_id }
    cosmosdb_account_ids   = { for k, v in module.mongodb : k => v.account_id }
    eventhub_namespace_ids = { for k, v in module.eventhub : k => v.namespace_id }
    storage_account_ids    = merge(
        { for k, v in module.storage_account : k => v.id },
        { for k, v in module.function_app : "${k}-storage" => v.storage_account_id }
    )

    # Compute resources (compute group)
    linux_vm_ids = { for k, v in module.linux_vm : k => v.vm_id }

    depends_on = [module.project_keyvault]
}

module "postgresql" {
    source = "../modules/postgresql"

    for_each = local.postgresql_resources

    name                = "${local.metadata.project_name}-${each.key}-${local.metadata.environment}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = each.value.config
    tags                = local.common_tags
}

module "mongodb" {
    source = "../modules/mongodb"

    for_each = local.mongodb_resources

    name                = "${local.metadata.project_name}-${each.key}-${local.metadata.environment}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = each.value.config
    tags                = local.common_tags
}

module "keyvault" {
    source = "../modules/keyvault"

    for_each = local.keyvault_resources

    name                = "${local.metadata.project_name}-${each.key}-${local.metadata.environment}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = each.value.config
    tags                = local.common_tags
}

module "storage_account" {
    source = "../modules/storage-account"

    for_each = local.storage_resources

    name                = lower("${local.metadata.project_name}${each.key}${local.metadata.environment}")
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = each.value.config
    tags                = local.common_tags
}

module "static_web_app" {
    source = "../modules/static-web-app"

    for_each = local.static_web_app_resources

    name                = "swa-${local.metadata.project_name}-${each.key}-${local.metadata.environment}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = lookup(each.value, "config", {})
    tags                = local.common_tags
}

module "function_app" {
    source = "../modules/function-app"

    for_each = local.function_resources

    name                = "func-${local.metadata.project_name}-${each.key}-${local.metadata.environment}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = lookup(each.value, "config", {})
    tags                = local.common_tags
}

module "azure_sql" {
    source = "../modules/azure-sql"

    for_each = local.azure_sql_resources

    name                = "sql-${local.metadata.project_name}-${each.key}-${local.metadata.environment}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = lookup(each.value, "config", {})
    tags                = local.common_tags
}

module "eventhub" {
    source = "../modules/eventhub"

    for_each = local.eventhub_resources

    name                = "evhns-${local.metadata.project_name}-${each.key}-${local.metadata.environment}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = lookup(each.value, "config", {})
    tags                = local.common_tags
}

module "aks_namespace" {
    source = "../modules/aks-namespace"

    for_each = local.aks_namespace_resources

    name                = "${local.metadata.project_name}-${each.key}-${local.metadata.environment}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = lookup(each.value, "config", {})
    tags                = local.common_tags
}

module "linux_vm" {
    source = "../modules/linux-vm"

    for_each = local.vm_resources

    name                = "vm-${local.metadata.project_name}-${each.key}-${local.metadata.environment}"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = lookup(each.value, "config", {})
    tags                = local.common_tags
}

output "resource_group" {
    value = {
        name     = azurerm_resource_group.main.name
        location = azurerm_resource_group.main.location
        id       = azurerm_resource_group.main.id
    }
}

output "postgresql_servers" {
    value = { for k, v in module.postgresql : k => {
        fqdn      = v.server_fqdn
        server_id = v.server_id
        database  = v.database_name
    }}
}

output "storage_accounts" {
    value = { for k, v in module.storage_account : k => {
        name             = v.name
        primary_endpoint = v.primary_blob_endpoint
        containers       = v.containers
    }}
}

output "static_web_apps" {
    value = { for k, v in module.static_web_app : k => {
        name              = v.name
        default_host_name = v.default_host_name
        url               = "https://${v.default_host_name}"
    }}
}

output "function_apps" {
    value = { for k, v in module.function_app : k => {
        name             = v.name
        default_hostname = v.default_hostname
        url              = "https://${v.default_hostname}"
        principal_id     = v.principal_id
    }}
}

output "azure_sql_servers" {
    value = { for k, v in module.azure_sql : k => {
        server_name  = v.server_name
        server_fqdn  = v.server_fqdn
        databases    = v.databases
        principal_id = v.principal_id
    }}
}

output "eventhubs" {
    value = { for k, v in module.eventhub : k => {
        namespace_name = v.namespace_name
        namespace_id   = v.namespace_id
        hubs           = v.hubs
    }}
}

output "aks_namespaces" {
    value = { for k, v in module.aks_namespace : k => {
        namespace_name = v.namespace_name
        resource_quota = v.resource_quota
    }}
}

output "linux_vms" {
    value = { for k, v in module.linux_vm : k => {
        vm_name            = v.vm_name
        private_ip_address = v.private_ip_address
        public_ip_address  = v.public_ip_address
        admin_username     = v.admin_username
        principal_id       = v.principal_id
    }}
}

# -----------------------------------------------------------------------------
# Project Key Vault and RBAC Outputs
# -----------------------------------------------------------------------------

output "project_keyvault" {
    description = "Project Key Vault for secrets access"
    sensitive   = true
    value = {
        name      = module.project_keyvault.vault_name
        uri       = module.project_keyvault.vault_uri
        id        = module.project_keyvault.vault_id
        secrets   = keys(local.all_secrets)
    }
}

output "security_groups" {
    description = "Entra ID security groups for RBAC (only includes created groups)"
    value = local.enable_rbac ? module.project_rbac[0].group_names : {}
}

output "developer_access_info" {
    description = "Information for developers to access their resources"
    value = {
        keyvault_name = module.project_keyvault.vault_name
        keyvault_uri  = module.project_keyvault.vault_uri

        # Instructions for accessing secrets
        access_instructions = <<-EOT
            To retrieve secrets, use one of the following methods:

            1. Azure CLI:
               az keyvault secret show --vault-name ${module.project_keyvault.vault_name} --name <secret-name>

            2. Azure Portal:
               Navigate to Key Vault '${module.project_keyvault.vault_name}' > Secrets

            3. Application (Managed Identity):
               Your app's managed identity has been granted access automatically.
               Use Azure SDK to retrieve secrets at runtime.

            Available secrets: ${join(", ", keys(local.all_secrets))}
        EOT

        # Security groups (only shows groups that were created)
        security_groups = local.enable_rbac ? {
            for k, v in module.project_rbac[0].group_names : {
                "readers"   = "Resource Group Reader"
                "secrets"   = "Key Vault Secrets"
                "deployers" = "Deployers"
                "data"      = "Data Access"
                "compute"   = "Compute Access"
            }[k] => v
        } : {}

        groups_created = local.enable_rbac ? module.project_rbac[0].groups_created : []
    }
}
