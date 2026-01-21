# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Enterprise Infrastructure Self-Service Platform: A catalog-driven, multi-tenant infrastructure provisioning system that allows teams to request cloud resources via CLI, REST API, or web portal. Uses event-driven architecture with Azure Functions, Service Bus, Cosmos DB, and GitHub Actions for Terraform execution.

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

### Terraform
```bash
cd terraform/catalog
terraform init
terraform plan -var="config_file=../config.yaml"
terraform apply -auto-approve tfplan
```

### Full Platform Deployment
```bash
bash scripts/deploy-platform.sh    # Requires: ARM_SUBSCRIPTION_ID, ARM_TENANT_ID, GH_PAT
```

## Architecture

### Request Processing Flow
```
CLI/API → Azure Functions API Gateway → Service Bus Queues (prod/staging/dev)
→ GitHub Actions Queue Consumer (cron: every minute)
→ Provision Worker (parallel: up to 10 workers)
→ Terraform Apply → Azure Resources + Cosmos DB state tracking
```

### Key Components

1. **CLI** (`cli/infra_cli.py`) - Click-based Python CLI that submits YAML configs to API Gateway

2. **API Gateway** (`infrastructure/api-gateway/function_app.py`) - Azure Functions HTTP API that:
   - Validates YAML schema and policy (cost limits per environment)
   - Estimates infrastructure costs
   - Stores requests in Cosmos DB (partitioned by `requestId`)
   - Queues to Service Bus with environment-based priority

3. **Queue Consumer** (`.github/workflows/queue-consumer.yaml`) - Scheduled workflow that polls three Service Bus queues and dispatches to provision workers

4. **Provision Worker** (`.github/workflows/provision-worker.yaml`) - Reusable workflow that:
   - Updates Cosmos DB status to "processing"
   - Generates and applies Terraform configs
   - Captures outputs and marks completion

5. **Terraform Catalog** (`terraform/catalog/main.tf`) - Dynamic resource provisioning using YAML-driven for-each patterns. Supports: PostgreSQL, MongoDB, Key Vault, Storage Account, VMs, AKS namespaces, Function Apps, Event Hubs

6. **Terraform Modules** (`terraform/modules/`) - Reusable modules for each resource type

### Environment Separation
- Three Service Bus queues with priority: prod > staging > dev
- Cost limits enforced: prod ($10k), staging ($2k), dev ($500)
- Separate Terraform state per business-unit/environment/project in Azure Storage
- OIDC-based authentication for GitHub Actions runners

### Multi-Tenancy
- Business unit isolation via resource groups (pattern: `rg-{project}-{environment}`)
- State path: `{business_unit}/{environment}/{project}/terraform.tfstate`
- RBAC per business unit with metadata tagging for billing

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

### YAML Request Format
See `examples/` directory for templates. Basic structure:
```yaml
metadata:
  project: my-project
  environment: dev
  business_unit: engineering
  owner: team@example.com
resources:
  - type: postgresql
    name: mydb
    sku: B_Standard_B1ms
```

## Adding New Infrastructure Modules

When asked to add a new infrastructure module/resource type, follow these steps in order:

### Required Steps

1. **Add MODULE_DEFINITIONS entry** in `mcp-server/src/index.ts`:
   ```typescript
   const MODULE_DEFINITIONS: Record<string, ModuleDefinition> = {
     // Add new module here with all required fields:
     new_module: {
       name: "new_module",
       description: "Description of the resource",
       required_fields: ["name"],
       config_options: {
         // Define all configuration options
       },
       azure_resource: "Microsoft.ResourceType/resources",
       example: {
         type: "new_module",
         name: "example-name",
         config: {}
       }
     }
   };
   ```

2. **Create Terraform module** in `terraform/modules/new_module/`:
   - `main.tf` - Resource definitions
   - `variables.tf` - Input variables matching config_options
   - `outputs.tf` - Resource outputs

3. **Update Terraform catalog** in `terraform/catalog/main.tf`:
   - Add module block that references the new module
   - Use for_each pattern to iterate over resources of this type

4. **Sync the workflow template** (IMPORTANT - do not skip):
   ```bash
   ./scripts/sync-workflow-template.sh
   ```
   This updates `templates/infrastructure-workflow.yaml` with the new valid_types list.

5. **Commit all changes together** - The CI workflow `validate-module-sync.yaml` will fail if MODULE_DEFINITIONS and the workflow template are out of sync.

### Files to Update (Checklist)

- [ ] `mcp-server/src/index.ts` - MODULE_DEFINITIONS
- [ ] `terraform/modules/<new_module>/main.tf`
- [ ] `terraform/modules/<new_module>/variables.tf`
- [ ] `terraform/modules/<new_module>/outputs.tf`
- [ ] `terraform/catalog/main.tf` - Module reference
- [ ] `templates/infrastructure-workflow.yaml` - Run sync script

### Single Source of Truth

`MODULE_DEFINITIONS` in `mcp-server/src/index.ts` is the single source of truth for:
- MCP server tools (list_available_modules, analyze_files, generate_workflow)
- The `/schema/modules` API endpoint
- The workflow template valid_types list (via sync script)

The CI workflow `.github/workflows/validate-module-sync.yaml` validates that these stay in sync.

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

Every provisioned project automatically gets:
1. **Project Key Vault** (`kv-{project}-{env}`) - Stores all generated secrets
2. **Entra ID Security Groups** - Least-privilege access for owners
3. **Managed Identity Access** - Apps can read secrets at runtime

### Defining Owners in infrastructure.yaml

```yaml
metadata:
  project_name: myapp
  environment: dev
  business_unit: engineering
  cost_center: eng-123
  owners:                           # NEW: Array of owner emails
    - alice@company.com
    - bob@company.com
  location: centralus
```

### Security Groups Created

| Group | RBAC Role | Scope |
|-------|-----------|-------|
| `sg-{project}-{env}-readers` | Reader | Resource Group |
| `sg-{project}-{env}-secrets` | Key Vault Secrets User | Key Vault |
| `sg-{project}-{env}-deployers` | Website Contributor | Function Apps |
| `sg-{project}-{env}-data` | SQL DB Contributor, Storage Blob Data Contributor | Data stores |

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

**Note:** `Group.ReadWrite.All` and `GroupMember.ReadWrite.All` are NOT required because:
- Terraform creates groups with owners set
- Owners can manage membership via delegated administration

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
