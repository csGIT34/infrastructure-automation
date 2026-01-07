# Infrastructure Self-Service Platform

An enterprise-grade platform that enables development teams to provision Azure infrastructure through simple YAML configuration files. Teams submit infrastructure requests which are automatically validated, queued, and provisioned via Terraform.

## Architecture Overview

```
                                    +------------------+
                                    |   GitHub Repo    |
                                    | (YAML Requests)  |
                                    +--------+---------+
                                             |
                                             v
+----------------+              +------------------------+
|  API Gateway   |   REST API   |    Azure Service Bus   |
| (Azure Func)   +------------->|  (Message Queues)      |
+----------------+              |  - dev queue           |
                                |  - staging queue       |
                                |  - prod queue          |
                                +----------+-------------+
                                           |
                          +----------------+----------------+
                          |                                 |
                          v                                 v
              +-----------+-----------+        +-----------+-----------+
              |  GitHub Actions       |        |   Cosmos DB           |
              |  Queue Consumer       |        |   (Request Tracking)  |
              +-----------+-----------+        +-----------------------+
                          |
                          v
              +-----------+-----------+
              |  Provision Workers    |
              |  (Terraform Apply)    |
              +-----------+-----------+
                          |
                          v
              +-----------+-----------+
              |   Azure Resources     |
              |   (Created Infra)     |
              +-----------------------+
```

## Components

| Component | Description | Location |
|-----------|-------------|----------|
| **API Gateway** | Azure Function App that validates requests and queues them | `infrastructure/api-gateway/` |
| **Service Bus** | Message queues for dev/staging/prod environments | Azure resource |
| **Cosmos DB** | Tracks request status and history | Azure resource |
| **Queue Consumer** | GitHub Actions workflow that monitors queues | `.github/workflows/queue-consumer.yaml` |
| **Provision Worker** | Runs Terraform to create infrastructure | `.github/workflows/provision-worker.yaml` |
| **Terraform Catalog** | Modular Terraform configs for each resource type | `terraform/catalog/` |

## Azure Resources Required

Before using this platform, you need the following Azure resources:

| Resource | Purpose | Example Name |
|----------|---------|--------------|
| Resource Group | Contains platform infrastructure | `rg-infrastructure-api` |
| Function App | API Gateway for request submission | `func-infra-api-*` |
| Service Bus Namespace | Message queuing | `sb-infra-api-*` |
| Cosmos DB Account | Request tracking database | `cosmos-infra-api-*` |
| Storage Account | Terraform state storage | `stfuncapi*` |
| App Registration | OIDC authentication for GitHub Actions | `github-infrastructure-automation` |

## GitHub Secrets Required

Configure these secrets in your GitHub repository:

| Secret | Description |
|--------|-------------|
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `AZURE_CLIENT_ID` | App registration client ID (for queue-consumer) |
| `AZURE_CLIENT_ID_dev` | App registration client ID for dev environment |
| `AZURE_CLIENT_ID_staging` | App registration client ID for staging environment |
| `AZURE_CLIENT_ID_prod` | App registration client ID for prod environment |
| `SERVICEBUS_NAMESPACE` | Service Bus namespace name (without `.servicebus.windows.net`) |
| `COSMOS_ENDPOINT` | Cosmos DB endpoint URL |
| `TF_STATE_STORAGE_ACCOUNT` | Storage account name for Terraform state |

## Supported Resource Types

| Resource Type | Terraform Module | Description |
|--------------|------------------|-------------|
| `storage_account` | `terraform/modules/storage-account` | Azure Storage Account with optional containers |
| `postgresql` | `terraform/modules/postgresql` | Azure Database for PostgreSQL Flexible Server |
| `mongodb` | `terraform/modules/mongodb` | Azure Cosmos DB with MongoDB API |
| `keyvault` | `terraform/modules/keyvault` | Azure Key Vault for secrets management |
| `static_web_app` | `terraform/modules/static-web-app` | Azure Static Web App for hosting SPAs and static sites |

## How YAML Becomes Infrastructure

This section explains how your YAML configuration file is transformed into Azure resources.

### The Transformation Pipeline

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   YAML File     │────>│  Python Worker  │────>│   Terraform     │────>│ Azure Resources │
│  (Your Config)  │     │ (Writes config) │     │  (Reads YAML)   │     │   (Created)     │
└─────────────────┘     └─────────────────┘     └─────────────────┘     └─────────────────┘
```

**Step-by-step:**

1. **You submit YAML** via the portal or API
2. **Worker receives message** from Service Bus containing YAML
3. **Worker writes** `config.yaml` to the Terraform workspace
4. **Terraform reads** the YAML using `yamldecode()` function
5. **Terraform creates** Azure resources based on the configuration

### Terraform Architecture

The Terraform code is organized into two layers:

```
terraform/
├── catalog/
│   └── main.tf          # Main orchestrator - reads YAML, calls modules
└── modules/
    ├── storage-account/ # Storage Account module
    ├── postgresql/      # PostgreSQL module
    ├── mongodb/         # MongoDB (Cosmos DB) module
    └── keyvault/        # Key Vault module
```

### The Catalog (`terraform/catalog/main.tf`)

The catalog is the main Terraform configuration that:
1. Reads your YAML file
2. Parses metadata and resources
3. Creates the resource group
4. Calls the appropriate modules for each resource

**YAML Parsing:**

```hcl
variable "config_file" {
    description = "Path to YAML configuration file"
    type        = string
}

locals {
    # Read and decode the YAML file
    config   = yamldecode(file(var.config_file))
    metadata = local.config.metadata
    resources = local.config.resources
}
```

**Resource Filtering:**

The catalog filters resources by type to route them to the correct module:

```hcl
locals {
    # Filter resources by type
    postgresql_resources = [for idx, r in local.resources : merge(r, { index = idx }) if r.type == "postgresql"]
    mongodb_resources    = [for idx, r in local.resources : merge(r, { index = idx }) if r.type == "mongodb"]
    keyvault_resources   = [for idx, r in local.resources : merge(r, { index = idx }) if r.type == "keyvault"]
    storage_resources    = [for idx, r in local.resources : merge(r, { index = idx }) if r.type == "storage_account"]
}
```

**Resource Group Creation:**

Every project gets its own resource group:

```hcl
resource "azurerm_resource_group" "main" {
    name     = "rg-${local.metadata.project_name}-${local.metadata.environment}"
    location = lookup(local.metadata, "location", "eastus")
    tags     = local.common_tags
}
```

**Module Invocation:**

Each resource type is handled by a module using `for_each`:

```hcl
module "storage_account" {
    source   = "../modules/storage-account"
    for_each = { for r in local.storage_resources : r.index => r }

    name                = lower("${local.metadata.project_name}${each.value.name}${local.metadata.environment}")
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
    config              = each.value.config    # Passes your YAML config block
    tags                = local.common_tags
}
```

### Module Structure

Each module follows the same pattern:

```
modules/storage-account/
├── main.tf       # Resource definitions
├── variables.tf  # Input variables
└── outputs.tf    # Output values
```

**Standard Module Inputs:**

| Variable | Type | Description |
|----------|------|-------------|
| `name` | string | Resource name (generated from project + resource + env) |
| `resource_group_name` | string | Resource group to create resource in |
| `location` | string | Azure region |
| `config` | any | Your YAML `config` block (type-specific settings) |
| `tags` | map(string) | Resource tags (auto-generated from metadata) |

### How Config Maps to Resources

**Example: Storage Account**

Your YAML:
```yaml
resources:
  - type: storage_account
    name: data
    config:
      tier: Standard
      replication: GRS
      versioning: true
      soft_delete_days: 7
      containers:
        - name: uploads
          access_type: private
```

Terraform module reads `config` and uses `lookup()` with defaults:

```hcl
resource "azurerm_storage_account" "main" {
    name                     = var.name
    resource_group_name      = var.resource_group_name
    location                 = var.location
    account_tier             = lookup(var.config, "tier", "Standard")        # From YAML or default
    account_replication_type = lookup(var.config, "replication", "LRS")      # From YAML or default

    blob_properties {
        versioning_enabled = lookup(var.config, "versioning", false)         # From YAML or default
    }
}
```

**Example: PostgreSQL**

Your YAML:
```yaml
resources:
  - type: postgresql
    name: maindb
    config:
      version: "14"
      sku: B_Standard_B1ms
      storage_mb: 32768
      backup_retention_days: 7
```

Terraform module:
```hcl
resource "azurerm_postgresql_flexible_server" "main" {
    name                = var.name
    resource_group_name = var.resource_group_name
    location            = var.location
    version             = lookup(var.config, "version", "14")
    sku_name            = lookup(var.config, "sku", "B_Standard_B1ms")
    storage_mb          = lookup(var.config, "storage_mb", 32768)
    backup_retention_days = lookup(var.config, "backup_retention_days", 7)

    # Auto-generated secure password
    administrator_login    = "psqladmin"
    administrator_password = random_password.admin.result
}
```

### Config Options by Resource Type

#### Storage Account (`storage_account`)

| Config Key | Type | Default | Description |
|------------|------|---------|-------------|
| `tier` | string | `"Standard"` | Account tier (Standard, Premium) |
| `replication` | string | `"LRS"` | Replication type (LRS, GRS, ZRS, GZRS) |
| `versioning` | bool | `false` | Enable blob versioning |
| `soft_delete_days` | number | `null` | Soft delete retention days |
| `containers` | list | `[]` | List of containers to create |

Container options:
| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `name` | string | required | Container name |
| `access_type` | string | `"private"` | Access level (private, blob, container) |

#### PostgreSQL (`postgresql`)

| Config Key | Type | Default | Description |
|------------|------|---------|-------------|
| `version` | string | `"14"` | PostgreSQL version (11, 12, 13, 14, 15) |
| `sku` | string | `"B_Standard_B1ms"` | Server SKU |
| `storage_mb` | number | `32768` | Storage size in MB |
| `backup_retention_days` | number | `7` | Backup retention (7-35 days) |
| `geo_redundant_backup` | bool | `false` | Enable geo-redundant backups |

#### MongoDB (`mongodb`)

| Config Key | Type | Default | Description |
|------------|------|---------|-------------|
| `serverless` | bool | `false` | Use serverless tier |
| `consistency_level` | string | `"Session"` | Consistency level |
| `throughput` | number | `400` | Request units (if not serverless) |

#### Key Vault (`keyvault`)

| Config Key | Type | Default | Description |
|------------|------|---------|-------------|
| `sku` | string | `"standard"` | SKU (standard, premium) |
| `soft_delete_days` | number | `7` | Soft delete retention (7-90 days) |
| `purge_protection` | bool | `false` | Enable purge protection |
| `rbac_enabled` | bool | `true` | Use RBAC for access control |
| `default_action` | string | `"Allow"` | Network default action |

#### Static Web App (`static_web_app`)

| Config Key | Type | Default | Description |
|------------|------|---------|-------------|
| `sku_tier` | string | `"Free"` | SKU tier (Free, Standard) |
| `sku_size` | string | `"Free"` | SKU size (Free, Standard) |

### Automatic Tag Generation

All resources receive these tags automatically:

| Tag | Source |
|-----|--------|
| `Project` | `metadata.project_name` |
| `Environment` | `metadata.environment` |
| `BusinessUnit` | `metadata.business_unit` |
| `CostCenter` | `metadata.cost_center` |
| `Owner` | `metadata.owner_email` |
| `ManagedBy` | `"Terraform-SelfService"` |

Plus any custom tags from `metadata.tags`.

### State Management

Terraform state is stored in Azure Blob Storage:

```
Storage Account: stfuncapirrkkz6a8
Container: tfstate
Blob Path: {business_unit}/{environment}/{project_name}/terraform.tfstate
```

Example: `engineering/dev/myproject/terraform.tfstate`

This ensures:
- Each project has isolated state
- Multiple environments don't conflict
- State is secure and backed up
- OIDC authentication (no stored credentials)

## Request YAML Schema

Infrastructure requests use this YAML structure:

```yaml
metadata:
  project_name: my-project        # Required: Used in resource naming
  environment: dev                # Required: dev, staging, or prod
  business_unit: engineering      # Required: For cost allocation
  cost_center: CC-ENG-001         # Required: For billing
  owner_email: team@company.com   # Required: Contact email
  location: eastus                # Optional: Azure region (default: eastus)
  tags:                           # Optional: Additional tags
    Application: MyApp
    Team: Platform

resources:
  - type: storage_account         # Resource type
    name: data                    # Resource name suffix
    config:                       # Type-specific configuration
      tier: Standard
      replication: LRS
```

### Resource Naming Convention

Resources are named using this pattern:
- **Resource Group**: `rg-{project_name}-{environment}`
- **Storage Account**: `{project_name}{resource_name}{environment}` (lowercase, no hyphens, max 24 chars)
- **Other Resources**: `{project_name}-{resource_name}-{environment}`

## Managing Existing Infrastructure

The platform uses Terraform state to track deployed resources. You can add, modify, or remove resources from existing projects by submitting updated requests.

### How State Management Works

The Terraform state key is derived from your metadata:
```
{business_unit}/{environment}/{project_name}/terraform.tfstate
```

When you submit a request with the **same** `project_name`, `environment`, and `business_unit`, Terraform:
1. Loads the existing state file
2. Compares your new YAML against the current state
3. Only adds, modifies, or removes what changed

### Adding Resources to an Existing Project

Submit a new request with the same metadata but include the new resource in the list:

**Original request** (storage account only):
```yaml
metadata:
  project_name: myapp
  environment: dev
  business_unit: engineering
  cost_center: CC-ENG-001
  owner_email: team@company.com

resources:
  - type: storage_account
    name: data
    config:
      tier: Standard
      replication: LRS
```

**Updated request** (adds Key Vault):
```yaml
metadata:
  project_name: myapp              # Must match original
  environment: dev                 # Must match original
  business_unit: engineering       # Must match original
  cost_center: CC-ENG-001
  owner_email: team@company.com

resources:
  - type: storage_account          # Existing - will be unchanged
    name: data
    config:
      tier: Standard
      replication: LRS
  - type: keyvault                 # New - will be created
    name: secrets
    config:
      sku: standard
      rbac_enabled: true
```

Terraform will detect that the storage account already exists and only create the new Key Vault.

### Modifying Existing Resources

Change configuration values in the resource's `config` block:

```yaml
resources:
  - type: storage_account
    name: data
    config:
      tier: Standard
      replication: GRS              # Changed from LRS to GRS
      versioning: true              # Added new setting
```

### Removing Resources

To remove a resource, submit a request **without** that resource in the list. Terraform will destroy any resources that are no longer defined.

**Warning**: Always review your YAML carefully before submitting. Omitting a resource will delete it and any data it contains.

### Best Practices

1. **Always include all resources** - List every resource you want to keep, not just new ones
2. **Use version control** - Store your YAML files in Git to track changes over time
3. **Test in dev first** - Make changes in dev environment before staging/prod
4. **Review Terraform plans** - Check the workflow logs to see what Terraform plans to change

## GitOps Support

The platform supports a GitOps workflow where developers manage infrastructure directly from their application repositories. This provides a developer-friendly experience with full traceability through Git history.

### How GitOps Works

```
Developer Repo                    Infrastructure Platform
----------------                  ----------------------

1. Edit infrastructure.yaml
        │
        v
2. Create Pull Request ──────────> GitHub Action validates YAML
        │                                    │
        │                                    v
        │                          Posts preview comment on PR
        │                          showing what will be created
        │
        v
3. Merge to main ────────────────> GitHub Action submits to Service Bus
                                            │
                                            v
                                   Queue Consumer processes request
                                            │
                                            v
                                   Terraform provisions resources
```

### Benefits of GitOps

- **Version Control**: All infrastructure changes tracked in Git
- **Code Review**: Infrastructure changes go through PR review
- **Preview Before Apply**: See exactly what will be created before merging
- **Audit Trail**: Full history of who changed what and when
- **Self-Service**: Developers manage their own infrastructure

### Setting Up GitOps in Your Repository

This guide walks you through setting up infrastructure-as-code in your developer repository.

#### Prerequisites

Before you begin, obtain these from your platform team:
- `INFRA_SERVICE_BUS_SAS_KEY` - Service Bus key for submitting requests
- `INFRA_APP_ID` - GitHub App ID for triggering immediate processing
- `INFRA_APP_PRIVATE_KEY` - GitHub App private key (PEM format)

#### Step 1: Copy the Workflow Template

Copy the workflow template from this repository to your project:

```bash
# From your repository root
mkdir -p .github/workflows
curl -o .github/workflows/infrastructure.yaml \
  https://raw.githubusercontent.com/csGIT34/infrastructure-automation/main/templates/infrastructure-workflow.yaml
```

Or manually copy `templates/infrastructure-workflow.yaml` to `.github/workflows/infrastructure.yaml`.

#### Step 2: Create Your Infrastructure Configuration

Create `infrastructure.yaml` in your repository root:

```yaml
# infrastructure.yaml
metadata:
  project_name: myapp           # Used in resource naming (keep short)
  environment: dev              # dev, staging, or prod
  business_unit: engineering    # For cost allocation
  cost_center: CC-ENG-001       # For billing
  owner_email: team@example.com # Contact email for notifications
  location: centralus           # Azure region
  tags:                         # Optional additional tags
    Application: MyApp
    Team: Engineering

resources:
  # Storage account for application data
  - type: storage_account
    name: data
    config:
      tier: Standard
      replication: LRS
      containers:
        - name: uploads
          access_type: private

  # Static web app for frontend
  - type: static_web_app
    name: frontend
    config:
      sku_tier: Free
      sku_size: Free
```

#### Step 3: Configure Repository Secrets

Add these secrets to your repository (**Settings** > **Secrets and variables** > **Actions**):

| Secret | Description | How to Obtain |
|--------|-------------|---------------|
| `INFRA_SERVICE_BUS_SAS_KEY` | Service Bus SAS key | Platform team or Azure CLI (see below) |
| `INFRA_APP_ID` | GitHub App ID | Platform team |
| `INFRA_APP_PRIVATE_KEY` | GitHub App private key | Platform team |

**Getting the Service Bus key (if you have Azure access):**

```bash
az servicebus namespace authorization-rule keys list \
  --namespace-name sb-infra-api-rrkkz6a8 \
  --resource-group rg-infrastructure-api \
  --name RootManageSharedAccessKey \
  --query primaryKey -o tsv
```

#### Step 4: Test Your Setup

1. Create a feature branch and modify `infrastructure.yaml`
2. Open a Pull Request
3. The workflow will validate your YAML and post a plan preview comment
4. Merge to main to provision the infrastructure

### How the Plan Preview Works

The workflow calls the infrastructure platform's `/api/plan` endpoint, which:

1. **Queries Cosmos DB** for the last successful deployment of your project/environment
2. **Compares** your proposed YAML against the deployed state
3. **Returns a diff** showing what will be added, removed, or unchanged

This ensures accurate plan previews even if:
- A previous deployment failed partway through
- Someone manually modified resources in Azure
- The git history doesn't match the actual deployed state

**Example PR Comment:**

```
## Infrastructure Plan Preview

### Project Information
| Property | Value |
|----------|-------|
| Project Name | `myapp` |
| Environment | `dev` |
| Business Unit | `engineering` |
| Owner | `team@example.com` |

### Last Successful Deployment
| Property | Value |
|----------|-------|
| Request ID | `gitops-csGIT34-myapp-a1b2c3d-1704567890` |
| Deployed At | `2024-01-06T15:30:00Z` |

### Changes Summary (vs. Last Deployment)
| Added | Removed | Unchanged |
|-------|---------|-----------|
| 1 | 0 | 2 |

### Resource Changes

| Status | Type | Name | Azure Resource |
|--------|------|------|----------------|
| + **Add** | `keyvault` | `secrets` | `myapp-secrets-dev` |
| = No change | `storage_account` | `data` | `myappdatadev` |
| = No change | `static_web_app` | `frontend` | `swa-myapp-frontend-dev` |

### Resource Group
`rg-myapp-dev`

---
**This PR will modify infrastructure.** Review changes carefully before merging.

**On merge to main**, these changes will be automatically applied.

Track provisioning status at: https://wonderful-field-088efae10.1.azurestaticapps.net
```

### Immediate Processing

When you merge a PR, the workflow:
1. Submits your request to the Service Bus queue
2. Triggers the queue consumer workflow immediately via GitHub App
3. Provisioning starts within seconds (no waiting for scheduled runs)

Track your request status at the [Infrastructure Portal](https://wonderful-field-088efae10.1.azurestaticapps.net)

### Tracking Your Requests

GitOps requests have IDs in the format:
```
gitops-{owner}-{repo}-{commit-sha}-{timestamp}
```

Example: `gitops-csGIT34-BillTracker-e4a46b8-1704567890`

Look up the request status in the [Infrastructure Portal](https://wonderful-field-088efae10.1.azurestaticapps.net) "Request Lookup" tab.

### Example Repository

See [github.com/csGIT34/BillTracker](https://github.com/csGIT34/BillTracker) for a working example of GitOps infrastructure management.

### Troubleshooting GitOps

| Issue | Solution |
|-------|----------|
| PR comment says "Could not connect to plan API" | The API may be cold-starting. The workflow uses fallback logic showing all resources as additions. |
| "No previous deployment found" | This is normal for first-time deployments. All resources show as additions. |
| Merge succeeded but no resources created | Check the [queue consumer workflow](https://github.com/csGIT34/infrastructure-automation/actions/workflows/queue-consumer.yaml) for errors. |
| Resources created but status shows "failed" | Check the workflow logs for Terraform errors. The resources may have been partially created. |

## How to Test

### Prerequisites

1. Azure CLI installed and logged in
2. GitHub CLI installed and authenticated
3. PowerShell (for Windows) or Bash (for Linux/Mac)

### Step 1: Verify Azure Resources

```bash
# Check Service Bus queues
az servicebus queue list --namespace-name sb-infra-api-rrkkz6a8 \
  --resource-group rg-infrastructure-api --query "[].name" -o table

# Check Cosmos DB
az cosmosdb show --name cosmos-infra-api-rrkkz6a8 \
  --resource-group rg-infrastructure-api --query "{name:name, endpoint:documentEndpoint}" -o json

# Check Terraform state storage
az storage container list --account-name stfuncapirrkkz6a8 \
  --query "[].name" -o table
```

### Step 2: Send a Test Message

Use the `send-test-message.ps1` script to send a test request directly to Service Bus:

```powershell
# Windows PowerShell
.\send-test-message.ps1
```

The script sends a request to provision a storage account in the `dev` environment.

### Step 3: Trigger the Workflow

```bash
# Trigger the queue consumer workflow
gh workflow run queue-consumer.yaml --ref main

# Watch the workflow progress
gh run list --workflow=queue-consumer.yaml --limit 5
```

### Step 4: Verify Infrastructure Creation

```bash
# Check if the resource group was created
az group show --name rg-test01-dev --query "{name:name,location:location}" -o json

# List resources in the group
az resource list --resource-group rg-test01-dev --output table
```

### Step 5: Check Terraform State

```bash
# List state files in storage
az storage blob list --container-name tfstate \
  --account-name stfuncapirrkkz6a8 \
  --query "[].name" -o table
```

## GitHub Actions Workflows

### Queue Consumer (`queue-consumer.yaml`)

The queue consumer is the orchestrator that monitors Service Bus queues and triggers workers.

**Triggers:**
- **Immediate**: Via `repository_dispatch` when a GitOps workflow merges (uses GitHub App)
- **Scheduled**: Every 15 minutes as a fallback
- **Manual**: Via `workflow_dispatch`

```yaml
on:
  schedule:
    - cron: '*/15 * * * *'  # Fallback polling
  workflow_dispatch:         # Manual trigger
  repository_dispatch:       # Immediate trigger from GitOps workflows
    types: [infrastructure-request]
```

**Jobs:**

| Job | Purpose |
|-----|---------|
| `check-queues` | Checks message count in each environment's queue |
| `trigger-prod-workers` | Triggers workers for production queue (if messages exist) |
| `trigger-staging-workers` | Triggers workers for staging queue (if messages exist) |
| `trigger-dev-workers` | Triggers workers for dev queue (if messages exist) |

**Flow:**
```
check-queues
    │
    ├── has_prod_messages? ──yes──> trigger-prod-workers
    │
    ├── has_staging_messages? ──yes──> trigger-staging-workers
    │
    └── has_dev_messages? ──yes──> trigger-dev-workers
```

Each trigger job only runs if there are messages in that environment's queue.

### Provision Worker (`provision-worker.yaml`)

The provision worker is a reusable workflow that processes infrastructure requests.

**Inputs:**

| Input | Type | Description |
|-------|------|-------------|
| `queue_name` | string | Service Bus queue to consume from |
| `environment` | string | Environment name (dev/staging/prod) |
| `runner_labels` | string | JSON array of runner labels |
| `max_parallel` | number | Maximum concurrent workers (default: 10) |

**Worker Matrix:**

The worker uses a matrix strategy to spawn multiple parallel workers:

```yaml
strategy:
    max-parallel: ${{ inputs.max_parallel }}
    matrix:
        worker: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
```

This creates up to 10 worker jobs that run in parallel, each competing to consume messages from the queue.

**Why Multiple Workers?**

- **Parallel processing**: Multiple requests can be processed simultaneously
- **Scalability**: Handle bursts of requests efficiently
- **Competing consumers**: Workers use Service Bus peek-lock to ensure each message is processed by only one worker
- **Fault tolerance**: If one worker fails, others continue processing

**Worker Behavior:**

```
Worker 1 ──┐
Worker 2 ──┼──> Service Bus Queue ──> Only ONE worker gets each message
Worker 3 ──┤
...        │
Worker 10 ─┘
```

Each worker:
1. Attempts to receive ONE message from the queue (with 5-second timeout)
2. If no message available → exits successfully (job shows as green)
3. If message received → processes it exclusively via peek-lock

**Processing Steps:**

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Receive Message (peek-lock)                              │
│    └─ Message is locked, invisible to other workers         │
├─────────────────────────────────────────────────────────────┤
│ 2. Parse YAML Configuration                                 │
│    └─ Extract metadata and resource definitions             │
├─────────────────────────────────────────────────────────────┤
│ 3. Update Cosmos DB → status: "processing"                  │
│    └─ Records github_run_id and github_run_url              │
├─────────────────────────────────────────────────────────────┤
│ 4. Run Terraform                                            │
│    ├─ terraform init (with remote state backend)            │
│    ├─ terraform plan (generates execution plan)             │
│    └─ terraform apply (provisions infrastructure)           │
├─────────────────────────────────────────────────────────────┤
│ 5a. SUCCESS:                                                │
│     ├─ Update Cosmos DB → status: "completed"               │
│     ├─ Store terraform_outputs in Cosmos DB                 │
│     └─ Complete message (removes from queue)                │
├─────────────────────────────────────────────────────────────┤
│ 5b. FAILURE:                                                │
│     ├─ Update Cosmos DB → status: "failed"                  │
│     ├─ Store error_message in Cosmos DB                     │
│     └─ Abandon message (returns to queue for retry)         │
└─────────────────────────────────────────────────────────────┘
```

**Environment Configuration:**

| Environment | Queue Name | Max Parallel | Runner Labels |
|-------------|------------|--------------|---------------|
| prod | `infrastructure-requests-prod` | 3 | `["self-hosted", "linux", "local"]` |
| staging | `infrastructure-requests-staging` | 3 | `["self-hosted", "linux", "local"]` |
| dev | `infrastructure-requests-dev` | 5 | `["ubuntu-latest"]` |

**Understanding Workflow Runs:**

When you see workflow runs like:
```
trigger-dev-workers / process-requests (1)  ✓
trigger-dev-workers / process-requests (2)  ✓
trigger-dev-workers / process-requests (3)  ✓
...
trigger-dev-workers / process-requests (10) ✓
```

This is normal! Each number represents a worker in the matrix:
- Workers that found and processed a message will show actual Terraform output
- Workers that found no messages will show "No messages in queue" and exit cleanly
- Only workers that encounter errors will show as failed (red)

## Runner Configuration

### Self-Hosted Runners (Recommended for Production)

The platform is designed to work with self-hosted GitHub Actions runners. Configure runner labels in `queue-consumer.yaml`:

```yaml
# For local k3s cluster runners
runner_labels: '["self-hosted", "linux", "local"]'

# For AKS runners
runner_labels: '["self-hosted", "linux", "infrastructure"]'
```

**Requirements for self-hosted runners:**
- Azure CLI installed
- Terraform installed
- Python 3.11+ with pip
- Network access to Azure APIs

See `infrastructure/local-runners/` for k3s-based runner deployment.

### GitHub-Hosted Runners (For Testing)

For development/testing, use GitHub-hosted runners:

```yaml
runner_labels: '["ubuntu-latest"]'
```

## Troubleshooting

### Common Issues

#### 1. State Lock Error
```
Error: Error acquiring the state lock
Error message: state blob is already locked
```

**Solution**: Break the lease on the state blob:
```bash
az storage blob lease break \
  --blob-name "business_unit/environment/project_name/terraform.tfstate" \
  --container-name tfstate \
  --account-name stfuncapirrkkz6a8
```

#### 2. Authorization Failed
```
Error: AuthorizationFailed - does not have authorization to perform action
```

**Solution**: Ensure the service principal has Contributor role at subscription level:
```bash
az role assignment create \
  --assignee-object-id <service-principal-object-id> \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope "/subscriptions/<subscription-id>"
```

#### 3. Storage Account Name Too Long
```
Error: name can only consist of lowercase letters and numbers, and must be between 3 and 24 characters
```

**Solution**: Use shorter project and resource names. The storage account name is generated as:
`{project_name}{resource_name}{environment}` - total must be <= 24 characters.

#### 4. Messages Going to Dead Letter Queue

Check the dead letter queue count:
```bash
az servicebus queue show --name infrastructure-requests-dev \
  --namespace-name sb-infra-api-rrkkz6a8 \
  --resource-group rg-infrastructure-api \
  --query "{active:countDetails.activeMessageCount, deadLetter:countDetails.deadLetterMessageCount}" -o json
```

View workflow logs for failure details:
```bash
gh run view <run-id> --log-failed
```

### Checking Logs

```bash
# List recent workflow runs
gh run list --workflow=queue-consumer.yaml --limit 10

# View specific run logs
gh run view <run-id> --log

# View only failed job logs
gh run view <run-id> --log-failed
```

## Example Requests

See the `examples/` directory for sample infrastructure configurations:

- `web-app-stack.yaml` - Complete web application with PostgreSQL, Key Vault, and Storage
- `microservices.yaml` - Microservices infrastructure template
- `data-pipeline.yaml` - Data processing pipeline resources

## Cost Management

The platform includes basic cost estimation and limits:

| Environment | Cost Limit (Monthly) |
|-------------|---------------------|
| dev | $500 |
| staging | $2,000 |
| prod | $10,000 |

Cost estimates are calculated based on resource types in the request.

## Security

- **OIDC Authentication**: GitHub Actions uses OpenID Connect to authenticate with Azure (no stored credentials)
- **Federated Credentials**: Each environment can have separate credentials
- **RBAC**: Service principal has Contributor role for resource provisioning
- **Terraform State**: Stored in Azure Blob Storage with Azure AD authentication
- **Service Bus**: Uses Shared Access Signatures for message operations

## Directory Structure

```
infrastructure-automation/
├── .github/
│   └── workflows/
│       ├── queue-consumer.yaml      # Monitors Service Bus queues
│       └── provision-worker.yaml    # Runs Terraform
├── infrastructure/
│   ├── api-gateway/                 # Azure Function App
│   ├── local-runners/               # Self-hosted runner setup
│   └── aks-runners/                 # AKS-based runners
├── terraform/
│   ├── catalog/                     # Main Terraform config
│   └── modules/                     # Resource modules
│       ├── storage-account/
│       ├── postgresql/
│       ├── mongodb/
│       └── keyvault/
├── examples/                        # Sample YAML configurations
├── cli/                             # CLI tool (optional)
└── send-test-message.ps1           # Test script
```

## License

Internal use only. Contact the Platform team for questions.
