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

**Schedule:** Runs every minute via cron, or can be triggered manually.

```yaml
on:
  schedule:
    - cron: '* * * * *'
  workflow_dispatch:  # Manual trigger
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
