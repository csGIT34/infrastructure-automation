# Infrastructure Platform - DevOps Team Guide

This guide is the complete reference for DevOps engineers who manage and extend the Infrastructure Self-Service Platform. It covers everything from day-to-day operations to creating new modules and patterns.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Platform Components](#platform-components)
3. [Creating a New Terraform Module](#creating-a-new-terraform-module)
4. [Creating a New Pattern](#creating-a-new-pattern)
5. [Integration Checklist](#integration-checklist)
6. [Testing Framework](#testing-framework)
7. [CI/CD Pipelines](#cicd-pipelines)
8. [Pattern Versioning](#pattern-versioning)
9. [Day-to-Day Operations](#day-to-day-operations)
10. [Troubleshooting](#troubleshooting)
11. [Security & Permissions](#security--permissions)

---

## Architecture Overview

### How the Platform Works

```
+-----------------------------------------------------------------------------+
|                              DEVELOPER WORKFLOW                              |
+-----------------------------------------------------------------------------+
|                                                                             |
|  1. Developer creates infrastructure.yaml in their repo                     |
|  2. Opens PR -> Validation workflow posts plan preview                      |
|  3. Merges PR -> repository_dispatch triggers provisioning                  |
|  4. Receives GitHub issue with results (success or failure)                 |
|                                                                             |
+-----------------------------------------------------------------------------+
                                     |
                                     v
+-----------------------------------------------------------------------------+
|                         INFRASTRUCTURE-AUTOMATION REPO                       |
+-----------------------------------------------------------------------------+
|                                                                             |
|  +------------------+    +------------------+    +------------------+        |
|  | Pattern Request  |--->| resolve-pattern  |--->| Terraform        |        |
|  | (YAML)           |    | (Python)         |    | Apply            |        |
|  +------------------+    +------------------+    +------------------+        |
|           |                       |                       |                 |
|           |                       v                       v                 |
|           |              +------------------+    +------------------+        |
|           |              | config/patterns/ |    | terraform/       |        |
|           |              | (sizing, schema) |    | patterns/        |        |
|           |              +------------------+    +------------------+        |
|           |                                              |                  |
|           v                                              v                  |
|  +------------------+                          +------------------+          |
|  | MCP Server       |                          | terraform/       |          |
|  | (AI integration) |                          | modules/         |          |
|  +------------------+                          +------------------+          |
|                                                                             |
+-----------------------------------------------------------------------------+
```

### Key Directories

| Directory | Purpose |
|-----------|---------|
| `terraform/modules/` | Reusable Terraform modules (building blocks) |
| `terraform/patterns/` | Pattern compositions (what developers request) |
| `config/patterns/` | Pattern metadata (sizing, costs, schema) |
| `mcp-server/src/` | MCP server pattern definitions (AI integration) |
| `templates/` | GitOps workflow template for consuming repos |
| `scripts/` | Python utilities for pattern resolution |
| `terraform/tests/` | Terraform test framework |
| `web/` | Self-service portal |

### Source of Truth

**`config/patterns/*.yaml`** is the single source of truth for pattern definitions. The following files are **auto-generated** from these pattern files:

| Generated File | Purpose |
|----------------|---------|
| `schemas/infrastructure.yaml.json` | JSON Schema for IDE validation (VS Code autocomplete) |
| `web/index.html` | Portal PATTERNS_DATA section |
| `templates/infrastructure-workflow.yaml` | valid_patterns list |
| `mcp-server/src/patterns.generated.json` | MCP server pattern data |

**Regenerate after editing patterns:**
```bash
python3 scripts/generate-schema.py
```

The CI workflow `validate-module-sync.yaml` enforces sync and will fail if generated files are out of date. You can also trigger it manually via workflow_dispatch.

---

## Platform Components

### 1. Terraform Modules (`terraform/modules/`)

Reusable infrastructure building blocks:

| Module | Description |
|--------|-------------|
| `naming` | Generates consistent resource names |
| `security-groups` | Creates Entra ID groups with owner delegation |
| `rbac-assignments` | Azure RBAC role assignments |
| `access-review` | Entra ID access reviews |
| `diagnostic-settings` | Log Analytics integration |
| `private-endpoint` | Private endpoint + DNS |
| `keyvault` | Azure Key Vault |
| `storage-account` | Storage Account |
| `postgresql` | PostgreSQL Flexible Server |
| `mongodb` | Cosmos DB MongoDB API |
| `azure-sql` | Azure SQL Database |
| `function-app` | Azure Functions |
| `eventhub` | Event Hubs namespace |
| `static-web-app` | Static Web App |
| `linux-vm` | Linux Virtual Machine |
| `aks-namespace` | Kubernetes namespace |
| `network-rules` | Network security rules |
| `project-rbac` | Project-level RBAC |

### 2. Terraform Patterns (`terraform/patterns/`)

Curated infrastructure compositions that developers request:

| Pattern | Type | Components |
|---------|------|------------|
| `keyvault` | single | keyvault + security-groups + rbac + access-review |
| `postgresql` | single | postgresql + keyvault + security-groups + rbac |
| `mongodb` | single | mongodb + security-groups + rbac |
| `storage` | single | storage-account + security-groups + rbac |
| `function-app` | single | function-app + storage + keyvault + security-groups |
| `sql-database` | single | azure-sql + security-groups + rbac |
| `eventhub` | single | eventhub + security-groups + rbac |
| `linux-vm` | single | linux-vm + security-groups + rbac |
| `static-site` | single | static-web-app + security-groups + rbac |
| `aks-namespace` | single | aks-namespace + rbac |
| `web-app` | composite | static-site + function-app + postgresql |
| `api-backend` | composite | function-app + sql-database + keyvault |
| `microservice` | composite | aks-namespace + eventhub + storage |
| `data-pipeline` | composite | eventhub + function-app + storage + mongodb |

### 3. Scripts (`scripts/`)

| Script | Purpose |
|--------|---------|
| `resolve-pattern.py` | Resolves pattern requests to Terraform vars |
| `generate-portal-data.py` | Generates JSON for web portal |
| `sync-workflow-template.sh` | Syncs workflow template to consuming repos |

### 4. GitHub Workflows (`.github/workflows/`)

| Workflow | Purpose |
|----------|---------|
| `provision.yaml` | Main provisioning workflow |
| `deploy-portal.yaml` | Portal deployment |
| `deploy-mcp-server.yaml` | MCP server deployment |
| `terraform-test.yaml` | Test runner |
| `validate-module-sync.yaml` | Sync validation gate |

### 5. Platform Services (`terraform/platform/`)

| Service | Purpose |
|---------|---------|
| `api/` | Dry Run API - validates pattern requests before provisioning |
| `portal/` | Self-service portal infrastructure (Azure Static Web App) |

### 6. Self-Service Portal (`web/`)

The portal provides a web interface for developers to:
- Browse available patterns and their configurations
- Generate `infrastructure.yaml` files
- **Validate configurations** before downloading (requires sign-in)

**Portal Authentication:**
- Uses Entra ID (Azure AD) with MSAL.js
- Sign in to enable the "Validate Configuration" button
- Validation calls the Dry Run API to check patterns before commit

**Portal URL:** Deployed to Azure Static Web Apps (see `terraform output -state=terraform/platform/portal/terraform.tfstate`)

### 7. Dry Run API (`terraform/platform/api/`)

Pre-commit validation API that validates pattern requests without provisioning.

**Features:**
- Validates `infrastructure.yaml` syntax and schema
- Shows what components will be provisioned
- Provides estimated monthly costs
- Returns environment-specific features

**Authentication:** Entra ID OAuth 2.0 bearer tokens (EasyAuth)

**Endpoint:** `POST /api/dry-run`

See [`terraform/platform/api/README.md`](terraform/platform/api/README.md) for full API documentation.

---

## Creating a New Terraform Module

Modules are reusable building blocks. Create a new module when you need functionality that will be used by multiple patterns.

### Step 1: Create Module Directory

```bash
mkdir -p terraform/modules/redis
```

### Step 2: Create Module Files

**`terraform/modules/redis/main.tf`**:

```hcl
# terraform/modules/redis/main.tf
# Azure Redis Cache module

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
  }
}

variable "name" {
  description = "Redis cache name"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "config" {
  description = "Redis configuration"
  type = object({
    sku_name            = optional(string, "Basic")
    family              = optional(string, "C")
    capacity            = optional(number, 0)
    enable_non_ssl_port = optional(bool, false)
    minimum_tls_version = optional(string, "1.2")
  })
  default = {}
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

resource "azurerm_redis_cache" "main" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  capacity            = var.config.capacity
  family              = var.config.family
  sku_name            = var.config.sku_name
  enable_non_ssl_port = var.config.enable_non_ssl_port
  minimum_tls_version = var.config.minimum_tls_version
  tags                = var.tags
}

output "redis_id" {
  description = "Redis cache resource ID"
  value       = azurerm_redis_cache.main.id
}

output "redis_hostname" {
  description = "Redis hostname"
  value       = azurerm_redis_cache.main.hostname
}

output "redis_port" {
  description = "Redis SSL port"
  value       = azurerm_redis_cache.main.ssl_port
}

output "redis_primary_key" {
  description = "Redis primary access key"
  value       = azurerm_redis_cache.main.primary_access_key
  sensitive   = true
}
```

### Step 3: Create Module Test

Create `terraform/tests/modules/redis/redis.tftest.hcl` with test assertions.

### Step 4: Add to Naming Module (if needed)

If your resource type needs special naming, update `terraform/modules/naming/main.tf`:

```hcl
# Add to prefixes map
prefixes = {
  ...
  redis = "redis"
}
```

### Step 5: Run Tests

```bash
cd terraform/tests
./run-tests.sh -m redis
```

---

## Creating a New Pattern

Patterns are what developers request. Follow this complete checklist to add a new pattern.

### Complete Checklist

- [ ] **Step 1**: Create Terraform pattern in `terraform/patterns/{pattern}/`
- [ ] **Step 2**: Create pattern metadata in `config/patterns/{pattern}.yaml` (SOURCE OF TRUTH)
- [ ] **Step 3**: Regenerate derived files with `python3 scripts/generate-schema.py`
- [ ] **Step 4**: Create pattern test in `terraform/tests/patterns/{pattern}/`
- [ ] **Step 5**: Add example in `examples/`
- [ ] **Step 6**: Run validation and tests
- [ ] **Step 7**: Commit all files together

### Step 1: Create Terraform Pattern

Create `terraform/patterns/{pattern}/main.tf` with:

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
  backend "azurerm" {
    use_oidc = true
  }
}

# Standard variables from pattern resolution
variable "project" { type = string }
variable "environment" { type = string }
variable "name" { type = string }
variable "owners" { type = list(string) }
variable "business_unit" { type = string }
variable "pattern_name" { type = string }
variable "location" { type = string }

# Sizing-resolved variables
variable "sku" { type = string }
variable "enable_diagnostics" { type = bool }
variable "enable_access_review" { type = bool }

# Resource Group
module "naming" {
  source        = "../../modules/naming"
  project       = var.project
  environment   = var.environment
  resource_type = "resource_group"
  name          = var.name
  business_unit = var.business_unit
  pattern_name  = var.pattern_name
}

resource "azurerm_resource_group" "main" {
  name     = module.naming.resource_group_name
  location = var.location
  tags     = module.naming.tags
}

# Security Groups
module "security_groups" {
  source       = "../../modules/security-groups"
  project      = var.project
  environment  = var.environment
  groups       = [
    { suffix = "readers", description = "Read access" },
    { suffix = "admins", description = "Admin access" }
  ]
  owner_emails = var.owners
}

# RBAC Assignments
module "rbac" {
  source      = "../../modules/rbac-assignments"
  assignments = [...]
}

# Access Review (conditional)
module "access_review" {
  source = "../../modules/access-review"
  count  = var.enable_access_review ? 1 : 0
  ...
}

# Outputs
output "resource_group" { value = azurerm_resource_group.main.name }
output "security_groups" { value = module.security_groups.group_names }
output "access_info" { value = "..." }
```

### Step 2: Create Pattern Metadata

Create `config/patterns/{pattern}.yaml`:

```yaml
name: pattern-name
description: |
  Description of the pattern.

category: single-resource  # or composite
components:
  - base-resource
  - security-groups
  - rbac-assignments

use_cases:
  - Use case 1
  - Use case 2

sizing:
  small:
    dev:
      sku: basic
      enable_diagnostics: false
      enable_access_review: false
    staging:
      sku: standard
      enable_diagnostics: true
      enable_access_review: false
    prod:
      sku: premium
      enable_diagnostics: true
      enable_access_review: true
  medium:
    # ...
  large:
    # ...

config:
  required:
    - name
  optional:
    - some_option:
        type: boolean
        default: false

estimated_costs:
  small:
    dev: 10
    staging: 50
    prod: 100
  medium:
    dev: 30
    staging: 100
    prod: 200
  large:
    dev: 100
    staging: 200
    prod: 400
```

### Step 3: Regenerate Derived Files

Run the generation script to update all auto-generated files:

```bash
python3 scripts/generate-schema.py
```

This updates:
- `schemas/infrastructure.yaml.json` - JSON Schema for IDE validation
- `web/index.html` - Portal PATTERNS_DATA
- `templates/infrastructure-workflow.yaml` - valid_patterns list
- `mcp-server/src/patterns.generated.json` - MCP server data

Verify the changes:
```bash
python3 scripts/generate-schema.py --check
```

### Step 4: Create Pattern Test

Create test structure:

```
terraform/tests/patterns/{pattern}/
├── {pattern}.tftest.hcl
├── setup/
│   └── main.tf
└── {pattern}_pattern_test/
    └── main.tf
```

### Step 5: Add Example

Create `examples/{pattern}-pattern.yaml`:

```yaml
version: "1"
metadata:
  project: myapp
  environment: dev
  business_unit: engineering
  owners:
    - alice@example.com
  location: eastus

pattern: pattern-name
pattern_version: "1.0.0"
config:
  name: myresource
  size: small
```

### Step 6: Run Validation

```bash
# Check all generated files are in sync
python3 scripts/generate-schema.py --check

# Run tests
cd terraform/tests && ./run-tests.sh -p pattern-name
```

### Step 7: Commit All Together

```bash
# Manual files
git add terraform/patterns/{pattern}/
git add config/patterns/{pattern}.yaml
git add terraform/tests/patterns/{pattern}/
git add examples/{pattern}-pattern.yaml

# Auto-generated files
git add schemas/infrastructure.yaml.json
git add web/index.html
git add templates/infrastructure-workflow.yaml
git add mcp-server/src/patterns.generated.json

git commit -m "Add {pattern} pattern with security groups and RBAC"
```

---

## Integration Checklist

### Manual Files (you create/edit these)

| File/Location | Required | Purpose |
|--------------|----------|---------|
| `terraform/patterns/{pattern}/main.tf` | **Yes** | Pattern Terraform code |
| `config/patterns/{pattern}.yaml` | **Yes** | Pattern metadata (SOURCE OF TRUTH) |
| `terraform/tests/patterns/{pattern}/` | **Yes** | Pattern tests |
| `examples/{pattern}-pattern.yaml` | Recommended | Usage example |
| `terraform/modules/naming/main.tf` | If needed | Resource naming prefix |

### Auto-Generated Files (run `python3 scripts/generate-schema.py`)

| File/Location | Purpose |
|--------------|---------|
| `schemas/infrastructure.yaml.json` | JSON Schema for IDE validation |
| `web/index.html` | Portal PATTERNS_DATA section |
| `templates/infrastructure-workflow.yaml` | valid_patterns list |
| `mcp-server/src/patterns.generated.json` | MCP server pattern data |

The CI workflow `validate-module-sync.yaml` enforces sync and fails if generated files are out of date. You can trigger it manually via Actions > Validate Pattern Sync > Run workflow.

---

## Testing Framework

### Test Structure

```
terraform/tests/
├── run-tests.sh              # Main test runner
├── setup/                    # Shared test setup
│   ├── env.example           # Environment template
│   └── providers.tf          # Provider config
├── modules/                  # Module tests
│   ├── naming/               # Pure logic (no Azure)
│   ├── keyvault/
│   └── ...
└── patterns/                 # Pattern tests
    ├── keyvault/
    │   ├── keyvault.tftest.hcl
    │   ├── setup/
    │   └── keyvault_pattern_test/
    └── ...
```

### Running Tests

```bash
cd terraform/tests

# Quick validation (naming module only - no Azure)
./run-tests.sh --quick

# Test a specific module
./run-tests.sh -m keyvault

# Test a specific pattern
./run-tests.sh -p web-app

# Run all module tests
./run-tests.sh --modules

# Run all pattern tests
./run-tests.sh --patterns

# Run everything
./run-tests.sh --all
```

### Test Configuration

Create `.env` from example:

```bash
cp terraform/tests/setup/env.example terraform/tests/setup/.env
```

Required variables:

```bash
ARM_TENANT_ID=your-tenant-id
ARM_SUBSCRIPTION_ID=your-subscription-id
ARM_CLIENT_ID=your-client-id
ARM_CLIENT_SECRET=your-client-secret
TF_VAR_owner_email=your-email@company.com
```

---

## CI/CD Pipelines

### Provision Workflow (`provision.yaml`)

**Triggered by**: `repository_dispatch` from consuming repos

**Process**:
1. Parse base64-encoded YAML from payload
2. Resolve patterns using `scripts/resolve-pattern.py`
3. Run `terraform init` with remote state
4. Run `terraform plan` and `terraform apply`
5. Estimate costs with Infracost (if `INFRACOST_API_KEY` is configured)
6. Report status back to source repo (creates issue with results)

**Infracost Integration:**

When `INFRACOST_API_KEY` is configured, the workflow estimates Azure costs for provisioned patterns. Results appear in the provisioning result issue:
- Per-pattern cost column in the summary table
- "Cost Estimate" section with total monthly cost

To enable:
1. Get a free API key at [infracost.io](https://www.infracost.io/)
2. Add `INFRACOST_API_KEY` secret to the infrastructure-automation repo

If the secret is not configured, cost estimation is skipped silently.

### Deploy Portal Workflow (`deploy-portal.yaml`)

**Triggered by**: Push to `web/`, `config/patterns/`, `scripts/`

**Process**:
1. Generate portal data from YAML configs
2. Embed data in `web/index.html`
3. Deploy to Azure Static Web Apps

### Deploy MCP Server Workflow (`deploy-mcp-server.yaml`)

**Triggered by**: Push to `mcp-server/`

**Process**:
1. Build Docker image
2. Push to GitHub Container Registry
3. Deploy to Azure Container Apps

### Terraform Test Workflow (`terraform-test.yaml`)

**Triggered by**: PR to `terraform/`, schedule, manual

### Validate Module Sync (`validate-module-sync.yaml`)

**Triggered by**: PR/push to pattern-related files

Ensures all pattern sources are in sync.

### Pattern Release (`release.yaml`)

**Triggered by**: Git tags matching `*/v*` (e.g., `keyvault/v1.2.0`)

**Process**:
1. Parse pattern name and version from tag
2. Run tests for the pattern (skipped for v1.0.0 initial releases)
3. Generate changelog from commits
4. Create GitHub release with release notes
5. Update VERSION and CHANGELOG files in pattern directory

---

## Pattern Versioning

The platform uses **per-pattern versioning** with semantic versioning. Each pattern evolves independently.

### Version Scheme

| Version Change | Meaning | When to Use |
|----------------|---------|-------------|
| Major (X.0.0) | Breaking changes | Variable changes, resource replacements, behavior changes |
| Minor (0.X.0) | New features | New optional variables, new outputs, feature additions |
| Patch (0.0.X) | Bug fixes | Bug fixes, documentation, internal refactoring |

### Tag Format

Tags follow the pattern: `{pattern}/v{major}.{minor}.{patch}`

Examples:
- `keyvault/v1.0.0` - Initial release
- `keyvault/v1.1.0` - Added new feature
- `keyvault/v2.0.0` - Breaking change
- `postgresql/v1.0.1` - Bug fix

### Creating a Release

**Using the helper script (recommended):**

```bash
# Check current version
cat terraform/patterns/keyvault/VERSION

# Create release
./scripts/create-release.sh keyvault 1.2.0
```

The script will:
- Validate the pattern exists
- Validate version format
- Check you're on the main branch
- Show commits since last release
- Create and push the tag

**Manual process:**

```bash
# Create tag
git tag keyvault/v1.2.0

# Push tag to trigger release workflow
git push origin keyvault/v1.2.0
```

### Release Workflow

When a tag is pushed, `.github/workflows/release.yaml` automatically:

1. **Parses the tag** - Extracts pattern name and version
2. **Validates the pattern** - Ensures directory exists
3. **Runs tests** - Validates the pattern works (skipped for v1.0.0)
4. **Generates changelog** - From commits since last release
5. **Creates GitHub release** - With release notes
6. **Updates files** - VERSION and CHANGELOG.md in pattern directory

### Development Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                      Development Workflow                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Create feature branch                                       │
│     └─▶ git checkout -b feature/keyvault-new-option             │
│                                                                 │
│  2. Make changes to pattern/modules                             │
│     └─▶ Edit terraform/patterns/keyvault/main.tf                │
│                                                                 │
│  3. Open PR                                                     │
│     └─▶ CI runs tests for affected patterns                     │
│     └─▶ Smart detection: only tests changed patterns/modules    │
│                                                                 │
│  4. Merge to main                                               │
│     └─▶ Tests must pass                                         │
│                                                                 │
│  5. Create release tag when ready                               │
│     └─▶ ./scripts/create-release.sh keyvault 1.2.0             │
│     └─▶ Release workflow creates GitHub release                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Smart Test Detection

The CI workflow (`.github/workflows/terraform-test.yaml`) uses smart detection to run only relevant tests:

**Pattern-Module Dependencies:**
```
keyvault    → naming, keyvault, security-groups, rbac-assignments, access-review, diagnostic-settings, private-endpoint
postgresql  → naming, postgresql, keyvault, security-groups, rbac-assignments, access-review, diagnostic-settings, private-endpoint
web-app     → naming, static-web-app, function-app, postgresql, keyvault, storage-account, security-groups, rbac-assignments
...
```

If you change `terraform/modules/keyvault/`, tests run for:
- `keyvault` module
- All patterns that depend on it (`keyvault`, `api-backend`, `web-app`)

### Consumer Version Pinning

Consumers **must** pin to specific versions:

```yaml
pattern: keyvault
pattern_version: "1.2.0"  # Required
```

The provision workflow validates the version exists and checks out the tagged version of the pattern.

### Update Checker for Consumers

Consumers can use `templates/update-checker-workflow.yaml` to receive automated PRs when new versions are available:

- Runs weekly (configurable)
- Creates PRs with version bumps
- Includes changelog in PR description
- Highlights breaking changes (major versions)

### Versioning Files

| File | Location | Purpose |
|------|----------|---------|
| VERSION | `terraform/patterns/{pattern}/VERSION` | Current version number |
| CHANGELOG.md | `terraform/patterns/{pattern}/CHANGELOG.md` | Release history |
| create-release.sh | `scripts/create-release.sh` | Helper script |
| release.yaml | `.github/workflows/release.yaml` | Release workflow |

### Best Practices

1. **Commit messages**: Use conventional commits for automatic changelog categorization
   - `feat(keyvault): add soft-delete option` → Features section
   - `fix(keyvault): correct RBAC assignment` → Bug Fixes section
   - `feat!: rename sku variable` → Breaking Changes section

2. **Test before releasing**: Always ensure tests pass before creating a release tag

3. **Document breaking changes**: Major versions should have clear upgrade instructions

4. **Coordinate releases**: When making breaking changes, consider communicating to consumers before releasing

---

## Day-to-Day Operations

### Monitoring Provisioning

```bash
# List recent provision workflow runs
gh run list --workflow=provision.yaml --limit 10

# View specific run
gh run view <run-id> --log

# View failed steps only
gh run view <run-id> --log-failed
```

### Manual Provisioning

```bash
gh workflow run provision.yaml \
  -f repository=owner/repo \
  -f commit_sha=abc123 \
  -f yaml_content="$(base64 < infrastructure.yaml)"
```

### Checking Terraform State

```bash
# List state files
az storage blob list \
  --container-name tfstate \
  --account-name <storage_account> \
  --query "[].name" -o table
```

### Breaking State Locks

```bash
az storage blob lease break \
  --blob-name "{bu}/{env}/{project}/{pattern}-{name}/terraform.tfstate" \
  --container-name tfstate \
  --account-name <storage_account>
```

### Rebuilding Portal Data

```bash
python scripts/generate-portal-data.py --embed
```

### Rebuilding MCP Server

```bash
cd mcp-server
npm install
npm run build
npm run start  # Test locally
```

---

## Troubleshooting

### Pattern Sync Validation Failed

**Solution**: Ensure all integration points are updated:
1. `terraform/patterns/{pattern}/main.tf` exists
2. `config/patterns/{pattern}.yaml` exists
3. Pattern is in `mcp-server/src/index.ts` PATTERN_DEFINITIONS
4. Pattern is in `templates/infrastructure-workflow.yaml` valid_patterns

### Terraform Apply Failed

**Debug steps**:
1. Check workflow logs: `gh run view <id> --log-failed`
2. Check Azure permissions for service principal
3. Verify resource naming doesn't conflict
4. Check Azure resource limits/quotas

### Security Group Creation Failed

**Solution**: Verify service principal has Microsoft Graph permissions:
- `Group.Create`
- `Group.Read.All`
- `User.Read.All`

### MCP Server Not Responding

**Debug steps**:
1. Check container health: `az containerapp logs show ...`
2. Verify MCP server is running: `curl https://<url>/health`
3. Check SSE endpoint: `curl https://<url>/sse`

### Tests Failing

**Debug steps**:
1. Check Azure credentials in `.env`
2. Verify service principal permissions
3. Check for resource naming conflicts
4. Run cleanup: `terraform/tests/cleanup-keyvaults.sh`

---

## Security & Permissions

### Required Azure Permissions

**Subscription Level**:
- Contributor (create resources)
- User Access Administrator (create RBAC assignments)

**Key Vault Level**:
- Key Vault Secrets Officer (store secrets)

### Required Microsoft Graph Permissions

| Permission | Type | Purpose |
|------------|------|---------|
| `Group.Create` | Application | Create security groups |
| `Group.Read.All` | Application | Read group properties |
| `User.Read.All` | Application | Look up users by email |
| `Application.Read.All` | Application | Read application info |

### GitHub App Permissions

| Permission | Access | Purpose |
|------------|--------|---------|
| `contents` | Read | Read infrastructure.yaml |
| `statuses` | Write | Update commit status |
| `issues` | Write | Create result issues |
| `metadata` | Read | Basic repo access |

### Environment Isolation

Each environment uses a separate service principal:
- `AZURE_CLIENT_ID_dev`
- `AZURE_CLIENT_ID_staging`
- `AZURE_CLIENT_ID_prod`

### Terraform State Security

- State stored in Azure Blob Storage
- OIDC authentication (no stored credentials)
- State path: `{business_unit}/{environment}/{project}/{pattern}-{name}/terraform.tfstate`

---

## Quick Reference

### Common Commands

```bash
# Validate pattern request
python scripts/resolve-pattern.py examples/keyvault-pattern.yaml --validate

# Resolve to Terraform vars
python scripts/resolve-pattern.py examples/keyvault-pattern.yaml --output json

# Generate portal data
python scripts/generate-portal-data.py --embed

# Run quick tests
cd terraform/tests && ./run-tests.sh --quick

# Run pattern test
cd terraform/tests && ./run-tests.sh -p keyvault

# Build MCP server
cd mcp-server && npm run build

# Create a pattern release
./scripts/create-release.sh keyvault 1.2.0

# List releases
gh release list | grep keyvault/

# View release notes
gh release view keyvault/v1.0.0
```

### File Locations

| What | Where |
|------|-------|
| Pattern Terraform | `terraform/patterns/{pattern}/main.tf` |
| Pattern metadata | `config/patterns/{pattern}.yaml` |
| Pattern version | `terraform/patterns/{pattern}/VERSION` |
| Pattern changelog | `terraform/patterns/{pattern}/CHANGELOG.md` |
| MCP definitions | `mcp-server/src/index.ts` |
| Workflow template | `templates/infrastructure-workflow.yaml` |
| Update checker template | `templates/update-checker-workflow.yaml` |
| Release workflow | `.github/workflows/release.yaml` |
| Pattern tests | `terraform/tests/patterns/{pattern}/` |
| Module tests | `terraform/tests/modules/{module}/` |
| Examples | `examples/` |
| Portal | `web/index.html` |

### Adding a New Pattern (TL;DR)

1. Create `terraform/patterns/{pattern}/main.tf`
2. Create `terraform/patterns/{pattern}/VERSION` with `1.0.0`
3. Create `config/patterns/{pattern}.yaml`
4. Add to `PATTERN_DEFINITIONS` in `mcp-server/src/index.ts`
5. Add to `valid_patterns` in `templates/infrastructure-workflow.yaml`
6. Create `terraform/tests/patterns/{pattern}/`
7. Create `examples/{pattern}-pattern.yaml`
8. Commit all together
9. Create initial release: `./scripts/create-release.sh {pattern} 1.0.0`
