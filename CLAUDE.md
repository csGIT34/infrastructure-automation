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
# Validate a pattern request (single document)
python3 scripts/resolve-pattern.py examples/keyvault-pattern.yaml --validate

# Validate multi-document YAML
python3 scripts/resolve-pattern.py examples/multi-pattern.yaml --validate

# Resolve multi-document YAML to JSON (for provisioning workflow)
python3 scripts/resolve-pattern.py examples/multi-pattern.yaml --output multi-json

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
→ Provision workflow runs
→ Pattern Resolution → Terraform Apply → Azure Resources
→ Status + Issue created in source repo (success or failure)
```

### Feedback Loop

The provision workflow reports back to the source repository:

1. **Commit Status**: Updates the commit with pending/success/failure status
   - Visible as a check mark or X on the commit in GitHub
   - Links to the provisioning workflow run

2. **Issue Creation**: Creates an issue in the source repo with results
   - **Success**: Resource details, outputs, security groups, access instructions
   - **Failure**: Error details, troubleshooting tips, link to workflow logs

3. **Retry**: Developers can retry by pushing a new commit to `infrastructure.yaml`

### Key Components

1. **GitOps Workflow Template** (`templates/infrastructure-workflow.yaml`) - Template for consuming repos:
   - Validates pattern request schema
   - Shows plan preview on PR
   - Triggers provisioning via `repository_dispatch` on merge

2. **Provision Workflow** (`.github/workflows/provision.yaml`) - Triggered by `repository_dispatch`:
   - Receives base64-encoded infrastructure.yaml from source repo
   - Resolves pattern to Terraform variables
   - Runs `terraform apply` on the pattern directory
   - Reports status back to source repo (commit status + issue)

3. **Pattern Resolution** (`scripts/resolve-pattern.py`) - Resolves pattern requests:
   - Validates pattern name and config
   - Resolves t-shirt sizing based on environment
   - Evaluates conditional features (prod-only, etc.)
   - Supports multi-document YAML with `--output multi-json`
   - Outputs Terraform tfvars (single doc) or JSON array (multi-doc)

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

**GitHub App for Status Reporting:**
- `INFRA_APP_ID` - GitHub App ID (same app as consuming repos)
- `INFRA_APP_PRIVATE_KEY` - GitHub App private key (PEM format)

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
pattern_version: "1.0.0"  # Required - pin to specific version
config:
  name: secrets
  size: small  # Optional, defaults based on environment
```

### Multi-Pattern Requests

Multiple patterns can be provisioned in a single `infrastructure.yaml` using YAML multi-document format (documents separated by `---`). This is useful for:
- Provisioning related resources together
- Replacing old resources with new ones (destroy + create)
- Batch infrastructure changes

**Action Field:**
- `action: create` (default) - Provision new resources
- `action: destroy` - Tear down existing resources

**Execution Order:**
1. All **destroy** actions run first (to free up resources/names)
2. All **create** actions run after
3. Processing continues on failure (reports all results)

**Example (`examples/multi-pattern.yaml`):**
```yaml
# Document 0: Destroy old database
---
version: "1"
action: destroy
metadata:
  project: myapp
  environment: dev
  business_unit: engineering
  owners: [alice@company.com]
pattern: postgresql
config:
  name: olddb

# Document 1: Create new Key Vault
---
version: "1"
action: create  # Optional, 'create' is default
metadata:
  project: myapp
  environment: dev
  business_unit: engineering
  owners: [alice@company.com]
pattern: keyvault
config:
  name: secrets

# Document 2: Create new storage
---
version: "1"
metadata:
  project: myapp
  environment: dev
  business_unit: engineering
  owners: [alice@company.com]
pattern: storage
config:
  name: data
```

**Backward Compatibility:**
- Single-document files work unchanged
- Missing `action` field defaults to `create`
- No version bump needed

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

### GitHub App Permissions (Infrastructure Dispatch)

The GitHub App (`INFRA_APP_ID`) must be installed on **both** infrastructure-automation and consuming repos with these permissions:

| Permission | Access | Purpose |
|------------|--------|---------|
| `contents` | Read | Read infrastructure.yaml from source repos |
| `statuses` | Write | Update commit status (pending/success/failure) |
| `issues` | Write | Create results/failure issues in source repos |
| `metadata` | Read | Basic repo access |

**Installation:**
1. Create a GitHub App in your organization
2. Generate a private key
3. Install the app on infrastructure-automation repo
4. Install the app on each consuming repo
5. Add `INFRA_APP_ID` and `INFRA_APP_PRIVATE_KEY` to both repos' secrets

## Pattern Versioning

The platform uses **per-pattern versioning** with semantic versioning (semver). Each pattern has its own independent version lifecycle.

### Version Format

Tags follow the format: `{pattern}/v{major}.{minor}.{patch}`

Examples:
- `keyvault/v1.0.0` - Initial release
- `keyvault/v1.1.0` - New feature (minor bump)
- `keyvault/v2.0.0` - Breaking change (major bump)

### Creating a Release

Platform developers use git tags to create releases:

```bash
# Check current version
cat terraform/patterns/keyvault/VERSION

# Create release using helper script
./scripts/create-release.sh keyvault 1.2.0

# Or manually
git tag keyvault/v1.2.0
git push origin keyvault/v1.2.0
```

The release workflow (`.github/workflows/release.yaml`) automatically:
1. Validates tests pass for the pattern
2. Generates changelog from commits
3. Creates GitHub release
4. Updates VERSION and CHANGELOG files

### Version Pinning (Consumers)

Consumers **must** pin to a specific version in their `infrastructure.yaml`:

```yaml
pattern: keyvault
pattern_version: "1.2.0"  # Required
```

### Update Checker (Consumers)

Consumers can use the update checker workflow (`templates/update-checker-workflow.yaml`) to get Dependabot-style PRs when new versions are available.

### Development Workflow

1. Create feature branch
2. Make changes to patterns/modules
3. Open PR (CI runs tests for affected patterns)
4. Merge to main (tests must pass)
5. Create release tag when ready to ship

### Related Files

- `docs/versioning-strategy.md` - Full versioning strategy documentation
- `.github/workflows/terraform-test.yaml` - Smart test detection for PRs
- `.github/workflows/release.yaml` - Tag-triggered release workflow
- `templates/update-checker-workflow.yaml` - Consumer update checker
- `scripts/create-release.sh` - Helper script for creating releases

## Key Documentation

- `infrastructure-platform-guide.md` - Comprehensive platform guide
- `docs/versioning-strategy.md` - Pattern versioning strategy
