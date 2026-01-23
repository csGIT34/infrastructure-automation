# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Enterprise Infrastructure Self-Service Platform: A **pattern-based**, multi-tenant infrastructure provisioning system that allows teams to request cloud resources via CLI, REST API, or web portal. Developers interact **only through patterns** - curated, opinionated compositions that include all necessary supporting infrastructure.

Uses event-driven architecture with Azure Functions, Service Bus, Cosmos DB, and GitHub Actions for Terraform execution.

## Common Commands

### CLI Development
```bash
cd cli
pip install -e .                              # Install CLI in dev mode
infra provision <file.yaml> --email <email>   # Submit request
infra status <request-id>                     # Check status
```

### API Gateway (Local Testing)
```bash
cd infrastructure/api-gateway
pip install -r requirements.txt
func start                                    # Start locally
```

### Terraform (Pattern-Based)
```bash
# Work with a specific pattern
cd terraform/patterns/keyvault
terraform init
terraform plan -var-file=terraform.tfvars.json
terraform apply -auto-approve tfplan

# Resolve a pattern request to Terraform vars
python3 scripts/resolve-pattern.py examples/keyvault-pattern.yaml --output json
```

### Pattern Validation
```bash
# Validate a pattern request
python3 scripts/resolve-pattern.py examples/keyvault-pattern.yaml --validate

# Sync workflow template with patterns
./scripts/sync-workflow-template.sh
```

## Architecture

### Pattern-Based Design

Developers interact **only through patterns** - not individual modules. Each pattern is a curated composition that includes:
- Base resource (database, key vault, etc.)
- Security groups with owner delegation
- RBAC assignments
- Diagnostics (staging/prod)
- Access reviews (prod only)
- Optional private endpoints

```
┌─────────────────────────────────────────────────────────────────┐
│                    Developer Request                             │
│  pattern: keyvault                                               │
│  config: { name: myapp-secrets, size: small }                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Pattern Resolution                            │
│  scripts/resolve-pattern.py                                      │
│  - Validates pattern + config                                    │
│  - Resolves t-shirt sizing (small/medium/large)                 │
│  - Evaluates conditions (prod-only features)                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              Per-Pattern Terraform Config                        │
│  terraform/patterns/keyvault/                                    │
│  - Composes modules from terraform/modules/                      │
│  - Isolated state per pattern instance                           │
└─────────────────────────────────────────────────────────────────┘
```

### Request Processing Flow
```
CLI/API → Azure Functions API Gateway → Service Bus Queues (prod/staging/dev)
→ GitHub Actions Queue Consumer (cron: every minute)
→ Provision Worker (parallel: up to 10 workers)
→ Pattern Resolution → Terraform Apply → Azure Resources + Cosmos DB tracking
```

### Key Components

1. **CLI** (`cli/infra_cli.py`) - Click-based Python CLI that submits YAML configs to API Gateway

2. **API Gateway** (`infrastructure/api-gateway/function_app.py`) - Azure Functions HTTP API that:
   - Validates pattern request schema and policy (cost limits per environment)
   - Estimates infrastructure costs based on pattern + size
   - Stores requests in Cosmos DB (partitioned by `requestId`)
   - Queues to Service Bus with environment-based priority

3. **Queue Consumer** (`.github/workflows/queue-consumer.yaml`) - Scheduled workflow that polls three Service Bus queues and dispatches to provision workers

4. **Provision Worker** (`.github/workflows/provision-worker.yaml`) - Reusable workflow that:
   - Resolves pattern request to Terraform variables
   - Runs `terraform apply` on the pattern directory
   - Updates Cosmos DB status and captures outputs

5. **Pattern Resolution** (`scripts/resolve-pattern.py`) - Resolves pattern requests:
   - Validates pattern name and config
   - Resolves t-shirt sizing based on environment
   - Evaluates conditional features (prod-only, etc.)
   - Outputs Terraform tfvars

6. **Per-Pattern Terraform** (`terraform/patterns/`) - Each pattern has its own isolated Terraform config that composes modules

7. **Utility Modules** (`terraform/modules/`) - Shared modules used by patterns:
   - `naming/` - Resource naming conventions
   - `security-groups/` - Entra ID group creation
   - `rbac-assignments/` - Azure role assignments
   - `private-endpoint/` - Private endpoint + DNS
   - `access-review/` - Entra access reviews
   - `diagnostic-settings/` - Log Analytics integration

### Environment Separation
- Three Service Bus queues with priority: prod > staging > dev
- Cost limits enforced: prod ($10k), staging ($2k), dev ($500)
- Separate Terraform state per pattern instance in Azure Storage
- State path: `{business_unit}/{environment}/{project}/{pattern}-{name}/terraform.tfstate`
- OIDC-based authentication for GitHub Actions runners

### Multi-Tenancy
- Business unit isolation via resource groups (pattern: `rg-{project}-{environment}`)
- RBAC per business unit with metadata tagging for billing
- Security groups with owner delegation per pattern

## Configuration

### Required Environment Variables

**API Gateway:**
- `SERVICEBUS_CONNECTION` - Service Bus connection string
- `COSMOS_DB_ENDPOINT` - Cosmos DB endpoint URL
- `COSMOS_DB_KEY` - Cosmos DB access key

**CLI:**
- `INFRA_API_URL` - API Gateway base URL
- `INFRA_API_KEY` - API authentication key

**Terraform State:**
- `TF_STATE_STORAGE_ACCOUNT` - Azure Storage account for state
- `TF_STATE_CONTAINER` - Blob container name

### Pattern Request Format

See `examples/` directory for templates. Basic structure:
```yaml
version: "1"
metadata:
  project: myapp
  environment: dev
  business_unit: engineering
  owners:
    - alice@company.com
    - bob@company.com
  location: eastus

pattern: keyvault
config:
  name: secrets
  size: small  # Optional, defaults based on environment
```

### Available Patterns

| Pattern | Category | Description |
|---------|----------|-------------|
| `keyvault` | single | Key Vault with security groups, RBAC, access reviews |
| `postgresql` | single | PostgreSQL Flexible Server with Key Vault for secrets |
| `mongodb` | single | Cosmos DB with MongoDB API |
| `storage` | single | Storage Account with containers |
| `function-app` | single | Azure Functions with storage and Key Vault |
| `sql-database` | single | Azure SQL Database |
| `eventhub` | single | Event Hubs namespace |
| `aks-namespace` | single | Kubernetes namespace in shared AKS cluster |
| `linux-vm` | single | Linux VM with managed disks |
| `static-site` | single | Static Web App for SPAs |
| `microservice` | composite | AKS namespace + Event Hub + Storage |
| `web-app` | composite | Static Web App + Function App + PostgreSQL |
| `api-backend` | composite | Function App + SQL Database + Key Vault |
| `data-pipeline` | composite | Event Hub + Function App + Storage + MongoDB |

### T-Shirt Sizing

Sizes resolve to environment-specific configurations:

| Size | Dev | Staging | Prod |
|------|-----|---------|------|
| small | Minimal resources | Basic resources | Production-ready |
| medium | Basic resources | Production-ready | High performance |
| large | Production-ready | High performance | Enterprise scale |

Default size by environment: dev=small, staging=medium, prod=medium

### Conditional Features

Features automatically enabled based on environment:
- **Diagnostics**: staging, prod
- **Access Reviews**: prod only
- **High Availability**: prod only
- **Geo-Redundant Backup**: prod only

## Adding New Infrastructure Patterns

When asked to add a new pattern, follow these steps:

### Required Steps

1. **Add PATTERN_DEFINITIONS entry** in `mcp-server/src/index.ts`:
   ```typescript
   const PATTERN_DEFINITIONS: Record<string, PatternDefinition> = {
     new_pattern: {
       name: "new_pattern",
       description: "Description of the pattern",
       category: "single",  // or "composite"
       components: ["base-resource", "security-groups", "rbac-assignments"],
       use_cases: ["Use case 1", "Use case 2"],
       config: {
         required: ["name"],
         optional: {
           some_option: { type: "boolean", default: false, description: "Description" }
         }
       },
       sizing: {
         small: { dev: {...}, staging: {...}, prod: {...} },
         medium: { dev: {...}, staging: {...}, prod: {...} },
         large: { dev: {...}, staging: {...}, prod: {...} }
       },
       estimated_costs: {
         small: { dev: 10, staging: 30, prod: 100 },
         medium: { dev: 30, staging: 100, prod: 200 },
         large: { dev: 100, staging: 200, prod: 400 }
       },
       detection_patterns: [
         { pattern: /regex_to_detect/i, weight: 5 }
       ]
     }
   };
   ```

2. **Create pattern Terraform config** in `terraform/patterns/new_pattern/`:
   - `main.tf` - Compose modules from terraform/modules/
   - `variables.tf` - Input variables (from pattern resolution)
   - `outputs.tf` - Resource outputs

3. **Create pattern metadata** in `config/patterns/new_pattern.yaml`:
   ```yaml
   name: new_pattern
   description: |
     Description of what this pattern provisions.
   category: single
   components:
     - base-resource
     - security-groups
     - rbac-assignments
   sizing:
     small:
       dev: { sku: "basic" }
       staging: { sku: "standard" }
       prod: { sku: "premium" }
   config:
     required:
       - name
     optional:
       - some_option:
           type: boolean
           default: false
   ```

4. **Sync the workflow template**:
   ```bash
   ./scripts/sync-workflow-template.sh
   ```

5. **Commit all changes together** - The CI workflow `validate-pattern-sync.yaml` will fail if patterns are out of sync.

### Files to Update (Checklist)

- [ ] `mcp-server/src/index.ts` - PATTERN_DEFINITIONS
- [ ] `terraform/patterns/<new_pattern>/main.tf`
- [ ] `terraform/patterns/<new_pattern>/variables.tf`
- [ ] `terraform/patterns/<new_pattern>/outputs.tf`
- [ ] `config/patterns/<new_pattern>.yaml` - Pattern metadata
- [ ] `templates/infrastructure-workflow.yaml` - Run sync script

### Single Source of Truth

`terraform/patterns/` is the source of truth for valid patterns. The CI workflow validates:
- Pattern directories match `config/patterns/*.yaml` metadata
- Workflow template `valid_patterns` list matches pattern directories
- MCP server `PATTERN_DEFINITIONS` includes all patterns

### Pattern Structure Template

Each pattern should follow this structure in `main.tf`:
```hcl
# 1. Naming module
module "naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "resource_type"
  name          = var.name
}

# 2. Resource Group
resource "azurerm_resource_group" "main" {
  name     = module.naming.resource_group_name
  location = var.location
  tags     = local.tags
}

# 3. Security Groups
module "security_groups" {
  source       = "../../modules/security-groups"
  project      = var.project
  environment  = var.environment
  groups       = [...]
  owner_emails = var.owners
}

# 4. Base Resource (pattern-specific)
module "main_resource" {
  source = "../../modules/<resource>"
  ...
}

# 5. RBAC Assignments
module "rbac" {
  source      = "../../modules/rbac-assignments"
  assignments = [...]
}

# 6. Diagnostics (conditional)
module "diagnostics" {
  source = "../../modules/diagnostic-settings"
  count  = var.enable_diagnostics ? 1 : 0
  ...
}

# 7. Access Review (conditional)
module "access_review" {
  source = "../../modules/access-review"
  count  = var.enable_access_review ? 1 : 0
  ...
}
```

## Operations & Maintenance

### Cleaning Up Stuck Requests

When infrastructure requests get stuck in "pending", "processing", or "queued" state, use the cleanup script:

```bash
# Preview what would be cleaned up (dry run)
./scripts/cleanup-stuck-requests.sh --dry-run

# Actually clean up stuck requests
./scripts/cleanup-stuck-requests.sh
```

The script will:
1. Query Cosmos DB for records with status: pending, processing, or queued
2. Update those records to status: failed with cleanup message
3. Remove corresponding messages from all Service Bus queues (dev, staging, prod)

**Prerequisites:**
- Azure CLI installed and logged in (`az login`)
- Python 3 with `azure-servicebus` package (`pip install azure-servicebus`)

**When to use:**
- Requests stuck for extended periods (workflow failures, runner issues)
- After infrastructure incidents that left orphaned requests
- Before maintenance windows to clear the queue

### Monitoring Queue Health

Check Service Bus queue status:
```bash
# Check all queues
for q in infrastructure-requests-dev infrastructure-requests-staging infrastructure-requests-prod; do
  az servicebus queue show \
    --namespace-name sb-infra-api-rrkkz6a8 \
    --resource-group rg-infrastructure-api \
    --name $q \
    --query "{queue: name, active: countDetails.activeMessageCount, dlq: countDetails.deadLetterMessageCount}" \
    -o json
done
```

### Managing Self-Hosted Runners (ArgoCD)

The GitHub Actions self-hosted runners are managed via ArgoCD. **Do not directly delete pods or modify k8s resources** - always use ArgoCD.

**Key files:**
- `infrastructure/local-runners/runner-deployment.yaml` - Runner configuration
- `infrastructure/local-runners/docker/Dockerfile` - Runner image definition

**To update the runner image:**

1. Make changes to `infrastructure/local-runners/docker/Dockerfile`
2. Push to main - the `build-runner-image.yaml` workflow builds and pushes to Docker Hub
3. Trigger ArgoCD sync to pull the new image:
   ```bash
   # Trigger hard refresh via kubectl
   kubectl patch application github-runners -n argocd \
     --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

   # Or trigger a sync
   kubectl patch application github-runners -n argocd \
     --type merge -p '{"operation":{"initiatedBy":{"username":"claude"},"sync":{"revision":"HEAD"}}}'
   ```

4. Verify pods are updated:
   ```bash
   kubectl get pods -n github-runners
   kubectl get application github-runners -n argocd
   ```

**To update runner configuration:**

1. Edit `infrastructure/local-runners/runner-deployment.yaml`
2. Commit and push to main
3. ArgoCD auto-syncs (or trigger manually as above)

**Verify runner packages:**
```bash
kubectl exec -n github-runners <pod-name> -c runner -- pip3 list | grep -E "yaml|azure"
```

**ArgoCD application details:**
- Application name: `github-runners`
- Namespace: `argocd`
- Target namespace: `github-runners`
- Source: `infrastructure/local-runners/` in this repo

**Image configuration:**
- Registry: `docker.io/csdock34/actions-runner:latest`
- `imagePullPolicy: Always` ensures new images are pulled on pod creation
- Packages included: pyyaml, azure-servicebus, azure-identity, azure-cosmos, terraform, azure-cli

### Reprocessing Failed Requests

To resubmit a failed request:
1. Find the request in Cosmos DB by requestId
2. Update status back to "pending"
3. Resubmit to Service Bus queue (or use CLI to submit fresh)

## Project RBAC and Secrets Management

### Overview

Every provisioned pattern automatically gets:
1. **Security Groups** - Entra ID groups with owner delegation
2. **RBAC Assignments** - Least-privilege access to resources
3. **Key Vault** (most patterns) - Stores generated secrets

### Defining Owners in infrastructure.yaml

```yaml
metadata:
  project: myapp
  environment: dev
  business_unit: engineering
  owners:
    - alice@company.com
    - bob@company.com
  location: eastus
```

### Security Groups Created

Each pattern creates groups like:
- `sg-{project}-{env}-{resource}-readers` - Read access
- `sg-{project}-{env}-{resource}-admins` - Full access

Owners are set as **group owners** in Entra ID, allowing them to manage membership without platform intervention.

### Accessing Secrets

Developers can access their secrets via:

```bash
# Azure CLI
az keyvault secret show --vault-name kv-myapp-dev --name sql-connection-string-mydb

# Azure Portal
# Navigate to Key Vault > Secrets

# Application (Managed Identity - automatic)
# Apps provisioned by the platform have Secrets User access
```

### Graph API Permissions (Terraform Service Principal)

The Terraform service principal requires these **least-privilege** Graph API permissions:

| Permission | Type | Purpose |
|------------|------|---------|
| `Group.Create` | Application | Create security groups |
| `Group.Read.All` | Application | Read group properties |
| `User.Read.All` | Application | Look up users by email |
| `Application.Read.All` | Application | Read application info |

### Azure RBAC Permissions (Terraform Service Principal)

On the subscription or target resource group scope:
- `Contributor` - Create and manage resources
- `User Access Administrator` - Create RBAC role assignments
- `Key Vault Secrets Officer` - Store secrets in Key Vault

## Error Handling Patterns

- Failed Service Bus messages go to DLQ for retry
- Failed requests marked as "failed" in Cosmos DB with error details
- Policy violations return 403 with specific violation message
- Schema validation errors return 400 with field-level details

## Home Lab Networking

The k3s cluster runs on Hyper-V with dual-NIC VMs for home network access.

### Network Architecture

```
Home Network (10.1.1.0/24)
├── k3s-master: 10.1.1.60 (eth1)
├── k3s-worker-1: 10.1.1.61 (eth1)
├── k3s-worker-2: 10.1.1.62 (eth1)
├── Traefik Ingress: 10.1.1.230 (MetalLB)
└── dnsmasq DNS: 10.1.1.231 (MetalLB)

Internal Cluster Network (10.10.10.0/24)
├── k3s-master: 10.10.10.10 (eth0)
├── k3s-worker-1: 10.10.10.11 (eth0)
└── k3s-worker-2: 10.10.10.12 (eth0)
```

### DNS Resolution

Network-wide DNS via dnsmasq at `10.1.1.231`. Configure router DHCP to use this as primary DNS.

**Current DNS records** (edit `infrastructure/local-runners/dnsmasq/configmap.yaml`):
- `argocd.lab` → 10.1.1.230 (Traefik)
- `workout.lab` → 10.1.1.230 (Traefik)
- `k3s-master.lab` → 10.1.1.60

**Adding DNS records:**
```yaml
# In dnsmasq configmap.yaml
address=/myapp.lab/10.1.1.230
```
Then: `kubectl rollout restart deployment dnsmasq -n dns`

### Creating Ingress for Apps

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: myapp-route
  namespace: myapp
spec:
  entryPoints:
    - web
  routes:
  - match: Host(`myapp.lab`)
    kind: Rule
    services:
    - name: myapp-service
      port: 80
```

### ArgoCD Applications

| App | Namespace | Description |
|-----|-----------|-------------|
| `cluster-networking` | metallb-system | MetalLB L2 load balancer |
| `dnsmasq` | dns | Network DNS server |
| `github-runners` | github-runners | Self-hosted Actions runners |

### Key Files

- `infrastructure/local-runners/networking/` - MetalLB, CoreDNS config
- `infrastructure/local-runners/dnsmasq/` - dnsmasq DNS server
- `infrastructure/local-runners/runner-deployment.yaml` - GitHub runners

### Useful Commands

```bash
# Check ArgoCD apps
kubectl get applications -n argocd

# Sync an app
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# Check LoadBalancer IPs
kubectl get svc -A | grep LoadBalancer

# Test DNS
nslookup argocd.lab 10.1.1.231

# Restart dnsmasq after config changes
kubectl rollout restart deployment dnsmasq -n dns
```

## Key Documentation

- `infrastructure-platform-guide.md` - Comprehensive platform guide
- `docs/ARCHITECTURE.md` - System design diagrams
- `docs/LOCAL-K8S-SETUP.md` - Local k3s cluster setup for self-hosted runners
- `infrastructure/local-runners/networking/README.md` - Network architecture details
- `infrastructure/local-runners/dnsmasq/README.md` - DNS server configuration
