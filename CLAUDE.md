# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Infrastructure Self-Service Platform: A **pattern-based** infrastructure provisioning system that allows teams to request cloud resources via GitOps (GitHub Actions). Developers interact **only through patterns** - curated, opinionated compositions that include all necessary supporting infrastructure.

Uses direct GitHub workflow triggers (`repository_dispatch`) for simple, reliable provisioning.

## Common Commands

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
Developer PR (infrastructure.yaml)
→ Validation + Plan Preview (PR comment)
→ Merge to main
→ repository_dispatch to infrastructure-automation repo
→ Provision workflow runs on self-hosted runner
→ Pattern Resolution → Terraform Apply → Azure Resources
```

### Key Components

1. **GitOps Workflow Template** (`templates/infrastructure-workflow.yaml`) - Template for consuming repos:
   - Validates pattern request schema
   - Shows plan preview on PR
   - Triggers provisioning via `repository_dispatch` on merge

2. **Provision Workflow** (`.github/workflows/provision.yaml`) - Triggered by `repository_dispatch`:
   - Downloads infrastructure.yaml from source repo
   - Resolves pattern to Terraform variables
   - Runs `terraform apply` on the pattern directory

3. **Pattern Resolution** (`scripts/resolve-pattern.py`) - Resolves pattern requests:
   - Validates pattern name and config
   - Resolves t-shirt sizing based on environment
   - Evaluates conditional features (prod-only, etc.)
   - Outputs Terraform tfvars

4. **Per-Pattern Terraform** (`terraform/patterns/`) - Each pattern has its own isolated Terraform config that composes modules

5. **Utility Modules** (`terraform/modules/`) - Shared modules used by patterns:
   - `naming/` - Resource naming conventions
   - `security-groups/` - Entra ID group creation
   - `rbac-assignments/` - Azure role assignments
   - `private-endpoint/` - Private endpoint + DNS
   - `access-review/` - Entra access reviews
   - `diagnostic-settings/` - Log Analytics integration

### Environment Separation
- Separate Terraform state per pattern instance in Azure Storage
- State path: `{business_unit}/{environment}/{project}/{pattern}-{name}/terraform.tfstate`
- OIDC-based authentication for GitHub Actions runners
- Environment-specific Azure client IDs (AZURE_CLIENT_ID_dev, AZURE_CLIENT_ID_staging, AZURE_CLIENT_ID_prod)

### Multi-Tenancy
- Business unit isolation via resource groups (pattern: `rg-{project}-{environment}`)
- RBAC per business unit with metadata tagging for billing
- Security groups with owner delegation per pattern

## Configuration

### Required Secrets (infrastructure-automation repo)

**Azure Authentication:**
- `AZURE_TENANT_ID` - Azure tenant ID
- `AZURE_SUBSCRIPTION_ID` - Azure subscription ID
- `AZURE_CLIENT_ID_dev` - Service principal for dev environment
- `AZURE_CLIENT_ID_staging` - Service principal for staging environment
- `AZURE_CLIENT_ID_prod` - Service principal for prod environment

**Terraform State:**
- `TF_STATE_STORAGE_ACCOUNT` - Azure Storage account for state
- `TF_STATE_CONTAINER` - Blob container name (default: tfstate)

### Required Secrets (consuming repos)

**GitHub App for Cross-Repo Dispatch:**
- `INFRA_APP_ID` - GitHub App ID
- `INFRA_APP_PRIVATE_KEY` - GitHub App private key (PEM format)

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

### Viewing Provisioning Status

Check GitHub Actions in the infrastructure-automation repository:
- Navigate to Actions tab
- Look for "Infrastructure Provision" workflow runs
- Each run shows the source repository, commit, and Terraform outputs

### Manual Provisioning

Trigger provisioning manually via workflow_dispatch:
```bash
gh workflow run provision.yaml \
  -f repository=owner/repo \
  -f commit_sha=abc123 \
  -f yaml_url=https://raw.githubusercontent.com/owner/repo/abc123/infrastructure.yaml
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
- Packages included: pyyaml, azure-identity, terraform, azure-cli

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
- `docs/LOCAL-K8S-SETUP.md` - Local k3s cluster setup for self-hosted runners
- `infrastructure/local-runners/networking/README.md` - Network architecture details
- `infrastructure/local-runners/dnsmasq/README.md` - DNS server configuration
