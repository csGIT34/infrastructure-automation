# Infrastructure Self-Service Platform

A **pattern-based** infrastructure provisioning platform that enables development teams to request Azure infrastructure through simple YAML configuration files. Teams interact only with curated infrastructure patterns - opinionated compositions that include all necessary supporting infrastructure (security groups, RBAC, diagnostics, access reviews).

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Quick Start](#quick-start)
  - [IDE Integration (VS Code)](#ide-integration-vs-code)
- [Infrastructure Patterns](#infrastructure-patterns)
- [Pattern Request Format](#pattern-request-format)
- [Pattern Versioning](#pattern-versioning)
- [T-Shirt Sizing](#t-shirt-sizing)
- [Multi-Pattern Requests](#multi-pattern-requests)
- [GitOps Workflow](#gitops-workflow)
- [Self-Service Portal](#self-service-portal)
- [MCP Server (AI Integration)](#mcp-server-ai-integration)
- [Terraform Modules](#terraform-modules)
- [Testing Framework](#testing-framework)
- [GitHub Actions Workflows](#github-actions-workflows)
- [Security & RBAC](#security--rbac)
- [Configuration Reference](#configuration-reference)
- [Troubleshooting](#troubleshooting)
- [Project Structure](#project-structure)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Developer Repository                                 │
│  infrastructure.yaml (pattern request)                                       │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ PR Created
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    GitOps Workflow (in developer repo)                       │
│  - Validates pattern request schema                                          │
│  - Shows plan preview in PR comment                                          │
│  - On merge: triggers repository_dispatch                                    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ repository_dispatch
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Provision Workflow (this repo)                            │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐          │
│  │ Pattern         │───▶│ Terraform       │───▶│ Azure           │          │
│  │ Resolution      │    │ Apply           │    │ Resources       │          │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘          │
│           │                                              │                   │
│           ▼                                              ▼                   │
│  scripts/resolve-pattern.py              Security Groups + RBAC + Resources  │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Status + Issue
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Feedback to Developer Repository                          │
│  - Commit status (success/failure)                                           │
│  - GitHub Issue with resource details or error info                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Concepts

| Concept | Description |
|---------|-------------|
| **Pattern** | A curated infrastructure composition (e.g., `keyvault`, `web-app`) |
| **T-Shirt Sizing** | Abstract sizes (small/medium/large) that resolve to cloud-specific SKUs |
| **Conditional Features** | Environment-specific features (diagnostics, access reviews) |
| **Owner Delegation** | Security groups with owners who can manage membership |

---

## Quick Start

### For Developers (Consuming the Platform)

1. **Copy the GitOps workflow** to your repository:
   ```bash
   mkdir -p .github/workflows
   curl -o .github/workflows/infrastructure.yaml \
     https://raw.githubusercontent.com/YOUR_ORG/infrastructure-automation/main/templates/infrastructure-workflow.yaml
   ```

2. **Create `infrastructure.yaml`** in your repository root:
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
     size: small
   ```

3. **Configure repository secrets**:
   - `INFRA_APP_ID` - GitHub App ID (from platform team)
   - `INFRA_APP_PRIVATE_KEY` - GitHub App private key

4. **Create a PR** with your `infrastructure.yaml` changes
5. **Review the plan preview** in the PR comment
6. **Merge to main** to provision infrastructure

### IDE Integration (VS Code)

Get autocomplete, validation, and hover documentation when editing `infrastructure.yaml` files.

1. **Install the YAML extension** ([Red Hat YAML](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml))

2. **Add schema association** to your repository's `.vscode/settings.json`:
   ```json
   {
     "yaml.schemas": {
       "https://raw.githubusercontent.com/csGIT34/infrastructure-automation/main/schemas/infrastructure.yaml.json": "infrastructure.yaml"
     }
   }
   ```

3. **Enjoy enhanced editing**:
   - Autocomplete for patterns, environments, locations, and config options
   - Inline validation with error highlighting
   - Hover documentation for all fields

**Alternative: User-level configuration**

Add to your VS Code user settings (`Cmd/Ctrl + ,` → Open Settings JSON):
```json
{
  "yaml.schemas": {
    "https://raw.githubusercontent.com/csGIT34/infrastructure-automation/main/schemas/infrastructure.yaml.json": "**/infrastructure.yaml"
  }
}
```

### For Platform Administrators

See [Configuration Reference](#configuration-reference) for required secrets and setup.

---

## Infrastructure Patterns

Patterns are curated infrastructure compositions. Each pattern includes the base resource plus supporting infrastructure (security groups, RBAC, diagnostics, access reviews).

### Single-Resource Patterns

| Pattern | Description | Components |
|---------|-------------|------------|
| `keyvault` | Azure Key Vault for secrets management | Key Vault, Security Groups, RBAC, Access Reviews |
| `postgresql` | PostgreSQL Flexible Server | PostgreSQL, Key Vault (secrets), Security Groups, RBAC |
| `mongodb` | Cosmos DB with MongoDB API | Cosmos DB, Security Groups, RBAC |
| `storage` | Storage Account with containers | Storage Account, Security Groups, RBAC |
| `function-app` | Azure Functions | Function App, Storage, Key Vault, Security Groups, RBAC |
| `sql-database` | Azure SQL Database | SQL Server, Database, Security Groups, RBAC |
| `eventhub` | Event Hubs namespace | Event Hub Namespace, Security Groups, RBAC |
| `linux-vm` | Linux Virtual Machine | VM, Managed Disk, NIC, Security Groups, RBAC |
| `static-site` | Static Web App for SPAs | Static Web App, Security Groups, RBAC |
| `aks-namespace` | Kubernetes namespace | Namespace, RBAC, Resource Quotas |

### Composite Patterns

Composite patterns provision multiple related resources as a cohesive stack:

| Pattern | Description | Components |
|---------|-------------|------------|
| `web-app` | Full web application stack | Static Web App + Function App + PostgreSQL |
| `api-backend` | API backend services | Function App + SQL Database + Key Vault |
| `microservice` | Microservices infrastructure | AKS Namespace + Event Hub + Storage |
| `data-pipeline` | Data processing pipeline | Event Hub + Function App + Storage + MongoDB |

### Pattern Details

Each pattern is defined in:
- **Terraform**: `terraform/patterns/{pattern}/` - Infrastructure code
- **Metadata**: `config/patterns/{pattern}.yaml` - Sizing, costs, config schema
- **MCP Server**: `mcp-server/src/index.ts` - AI integration definitions

---

## Pattern Request Format

### Basic Structure

```yaml
version: "1"
metadata:
  project: myapp              # Required: Used in resource naming
  environment: dev            # Required: dev, staging, or prod
  business_unit: engineering  # Required: For cost allocation and isolation
  owners:                     # Required: Entra ID users who own the resources
    - alice@company.com
    - bob@company.com
  location: eastus            # Optional: Azure region (default: eastus)

pattern: keyvault             # Required: Pattern name
pattern_version: "1.0.0"      # Required: Pinned version (semver)
config:                       # Pattern-specific configuration
  name: secrets               # Required: Resource name suffix
  size: small                 # Optional: T-shirt size (default by environment)
```

### Metadata Fields

| Field | Required | Description |
|-------|----------|-------------|
| `project` | Yes | Project identifier, used in resource naming (keep short) |
| `environment` | Yes | `dev`, `staging`, or `prod` |
| `business_unit` | Yes | Business unit for cost allocation |
| `owners` | Yes | List of Entra ID email addresses |
| `location` | No | Azure region (default: `eastus`) |

### Config Fields

Each pattern has its own config schema. Common fields:

| Field | Description |
|-------|-------------|
| `name` | Resource name suffix (required for all patterns) |
| `size` | T-shirt size: `small`, `medium`, `large` (optional) |

See pattern-specific config options in `config/patterns/{pattern}.yaml`.

---

## Pattern Versioning

The platform uses **per-pattern versioning** with semantic versioning (semver). Each pattern has its own independent version lifecycle, allowing patterns to evolve at different rates.

### Why Version Pinning?

- **Stability**: Your infrastructure won't change unexpectedly when patterns are updated
- **Controlled Upgrades**: You decide when to adopt new versions
- **Breaking Change Awareness**: Major version bumps signal breaking changes

### Version Format

Versions follow semantic versioning: `MAJOR.MINOR.PATCH`

| Version Change | Meaning | Example |
|----------------|---------|---------|
| Major (X.0.0) | Breaking changes | `1.0.0` → `2.0.0` |
| Minor (0.X.0) | New features, backward compatible | `1.0.0` → `1.1.0` |
| Patch (0.0.X) | Bug fixes, backward compatible | `1.0.0` → `1.0.1` |

### Checking Available Versions

```bash
# List all releases for a pattern
gh release list --repo YOUR_ORG/infrastructure-automation | grep "keyvault/"

# View release notes
gh release view keyvault/v1.0.0 --repo YOUR_ORG/infrastructure-automation
```

Or browse releases in the GitHub UI.

### Upgrading Versions

1. Check the [releases page](../../releases) for available versions and changelogs
2. Review release notes for breaking changes (major versions)
3. Update `pattern_version` in your `infrastructure.yaml`:
   ```yaml
   pattern_version: "1.1.0"  # Updated from 1.0.0
   ```
4. Open a PR to review the plan preview
5. Merge to apply the upgrade

### Automated Update Notifications

Use the update checker workflow to receive Dependabot-style PRs when new pattern versions are available:

1. Copy `templates/update-checker-workflow.yaml` to `.github/workflows/`
2. Configure the schedule (default: weekly)
3. Receive automated PRs with version bumps and changelogs

### Current Pattern Versions

All patterns are currently at version `1.0.0`. Check the [releases page](../../releases) for the latest versions.

---

## T-Shirt Sizing

T-shirt sizes abstract cloud-specific SKUs into simple choices:

| Size | Dev | Staging | Prod |
|------|-----|---------|------|
| `small` | Minimal resources | Basic resources | Production-ready |
| `medium` | Basic resources | Production-ready | High performance |
| `large` | Production-ready | High performance | Enterprise scale |

### Default Sizes by Environment

| Environment | Default Size |
|-------------|--------------|
| dev | small |
| staging | medium |
| prod | medium |

### Example: Key Vault Sizing

| Size | Dev SKU | Staging SKU | Prod SKU |
|------|---------|-------------|----------|
| small | standard | standard | premium |
| medium | standard | premium | premium |
| large | premium | premium | premium |

### Conditional Features

Features automatically enabled based on environment:

| Feature | Dev | Staging | Prod |
|---------|-----|---------|------|
| Diagnostics | No | Yes | Yes |
| Access Reviews | No | No | Yes |
| High Availability | No | No | Yes |
| Geo-Redundant Backup | No | No | Yes |

---

## Multi-Pattern Requests

Provision multiple patterns in a single request using YAML multi-document format:

```yaml
# Document 1: Destroy old database
---
version: "1"
action: destroy
metadata:
  project: myapp
  environment: dev
  business_unit: engineering
  owners: [alice@company.com]
pattern: postgresql
pattern_version: "1.0.0"
config:
  name: olddb

# Document 2: Create new Key Vault
---
version: "1"
action: create
metadata:
  project: myapp
  environment: dev
  business_unit: engineering
  owners: [alice@company.com]
pattern: keyvault
pattern_version: "1.0.0"
config:
  name: secrets

# Document 3: Create new storage
---
version: "1"
metadata:
  project: myapp
  environment: dev
  business_unit: engineering
  owners: [alice@company.com]
pattern: storage
pattern_version: "1.0.0"
config:
  name: data
```

### Action Field

| Action | Description |
|--------|-------------|
| `create` | Provision new resources (default) |
| `destroy` | Tear down existing resources |

### Execution Order

1. All **destroy** actions run first
2. All **create** actions run after
3. Processing continues on failure (reports all results)

---

## GitOps Workflow

The platform uses a GitOps approach where infrastructure is managed through Git:

```
Developer Repository                 Infrastructure Platform
--------------------                 ----------------------

1. Edit infrastructure.yaml
        │
        ▼
2. Create Pull Request ────────────▶ Validates YAML schema
        │                                    │
        │                                    ▼
        │                           Posts plan preview comment
        │
        ▼
3. Merge to main ──────────────────▶ Triggers repository_dispatch
                                            │
                                            ▼
                                    Provision workflow runs
                                            │
                                            ▼
                                    Reports status + creates issue
```

### Setting Up GitOps in Your Repository

1. **Copy the workflow template**:
   ```bash
   mkdir -p .github/workflows
   curl -o .github/workflows/infrastructure.yaml \
     https://raw.githubusercontent.com/YOUR_ORG/infrastructure-automation/main/templates/infrastructure-workflow.yaml
   ```

2. **Add repository secrets**:
   | Secret | Description |
   |--------|-------------|
   | `INFRA_APP_ID` | GitHub App ID |
   | `INFRA_APP_PRIVATE_KEY` | GitHub App private key (PEM format) |

3. **Create `infrastructure.yaml`** in your repository root

4. **Open a Pull Request** - the workflow posts a plan preview

5. **Merge to main** - infrastructure is provisioned

### Plan Preview

When you open a PR, the workflow posts a comment showing:
- Project information
- Resources to be added/removed/unchanged
- Estimated costs
- Security groups that will be created

### Feedback Loop

After provisioning, the platform reports back:

1. **Commit Status**: Success/failure indicator on the commit
2. **GitHub Issue**: Detailed results with:
   - Resource details and connection strings (on success)
   - Error details and troubleshooting tips (on failure)

---

## Self-Service Portal

The platform includes a web-based portal for browsing patterns and generating configurations.

### Features

**Pattern Builder Tab:**
- Interactive form to build pattern configurations
- T-shirt sizing selector (small/medium/large) with cost estimates
- Governance options (access reviews for prod)
- Live YAML preview with copy-to-clipboard
- Pattern version selection from available releases

**Setup Guide Tab:**
- Step-by-step instructions for consuming repositories
- GitHub App installation guide
- Create and destroy action examples with multi-document YAML

**Pattern Reference Tab:**
- Complete documentation for all patterns
- Quick navigation grouped by Single Resource and Composite patterns
- Search filter to find patterns by name or content
- T-shirt sizing details showing actual specs per environment
- Estimated monthly costs per size/environment

### Accessing the Portal

The portal is deployed to Azure Static Web Apps. Contact your platform team for the URL.

### Portal Architecture

```
web/
├── index.html              # Single-page application
└── staticwebapp.config.json # Azure Static Web App config
```

Pattern data is embedded in `index.html` during the CI/CD pipeline from `config/patterns/*.yaml`.

---

## MCP Server (AI Integration)

The platform includes a Model Context Protocol (MCP) server that enables AI assistants (like Claude) to:

- Analyze codebases and recommend infrastructure
- Generate valid `infrastructure.yaml` configurations
- Validate configurations against the schema
- Provide pattern documentation

### Setup for Claude Code

Add to your MCP settings (`.mcp.json`):

```json
{
  "mcpServers": {
    "infrastructure": {
      "command": "node",
      "args": ["/path/to/infrastructure-automation/mcp-server/dist/index.js"]
    }
  }
}
```

Or use the SSE endpoint for remote access:

```json
{
  "mcpServers": {
    "infrastructure": {
      "type": "sse",
      "url": "https://your-mcp-server.azurecontainerapps.io/sse"
    }
  }
}
```

### Available Tools

| Tool | Description |
|------|-------------|
| `list_patterns` | List all available infrastructure patterns |
| `get_pattern_details` | Get detailed info about a specific pattern |
| `analyze_codebase` | Analyze a codebase for infrastructure needs |
| `generate_infrastructure_yaml` | Generate a valid configuration |
| `validate_infrastructure_yaml` | Validate a configuration |

### Building the MCP Server

```bash
cd mcp-server
npm install
npm run build
```

### Running Locally

```bash
# Standard I/O mode (for Claude Code)
npm run start

# SSE mode (for web access)
npm run start:sse
```

---

## Terraform Modules

The platform uses modular Terraform code. Patterns compose these shared modules:

### Core Resource Modules

| Module | Description |
|--------|-------------|
| `keyvault` | Azure Key Vault with RBAC |
| `storage-account` | Storage Account with containers |
| `postgresql` | PostgreSQL Flexible Server |
| `mongodb` | Cosmos DB with MongoDB API |
| `azure-sql` | Azure SQL Database |
| `function-app` | Azure Functions with App Service |
| `eventhub` | Event Hubs namespace |
| `static-web-app` | Static Web App |
| `linux-vm` | Linux Virtual Machine |
| `aks-namespace` | Kubernetes namespace |

### Supporting Modules

| Module | Description |
|--------|-------------|
| `naming` | Consistent resource naming conventions |
| `security-groups` | Entra ID security groups with owner delegation |
| `rbac-assignments` | Azure RBAC role assignments |
| `access-review` | Entra ID access reviews |
| `diagnostic-settings` | Log Analytics integration |
| `private-endpoint` | Private endpoints with DNS |
| `network-rules` | Network security rules |
| `project-rbac` | Project-level RBAC |

### Module Location

All modules are in `terraform/modules/`.

### Pattern Composition

Each pattern in `terraform/patterns/{pattern}/` composes modules:

```hcl
# Example: keyvault pattern (terraform/patterns/keyvault/main.tf)

module "naming" {
  source = "../../modules/naming"
  ...
}

module "security_groups" {
  source = "../../modules/security-groups"
  ...
}

module "keyvault" {
  source = "../../modules/keyvault"
  ...
}

module "rbac" {
  source = "../../modules/rbac-assignments"
  ...
}

module "diagnostics" {
  source = "../../modules/diagnostic-settings"
  count  = var.enable_diagnostics ? 1 : 0
  ...
}

module "access_review" {
  source = "../../modules/access-review"
  count  = var.enable_access_review ? 1 : 0
  ...
}
```

---

## Testing Framework

The platform includes a comprehensive Terraform testing framework.

### Test Structure

```
terraform/tests/
├── run-tests.sh              # Main test runner
├── setup/                    # Test environment configuration
├── modules/                  # Module-level tests
│   ├── naming/               # Pure logic tests (no Azure)
│   ├── keyvault/
│   ├── storage-account/
│   └── ...
└── patterns/                 # Pattern integration tests
    ├── keyvault/
    ├── web-app/
    └── ...
```

### Running Tests

```bash
cd terraform/tests

# Quick validation (naming module only, no Azure resources)
./run-tests.sh --quick

# Test a specific module
./run-tests.sh -m keyvault

# Test a specific pattern
./run-tests.sh -p web-app

# Run all tests
./run-tests.sh --all
```

### Test Requirements

- Terraform 1.5+
- Azure CLI with logged-in session
- Service Principal with appropriate permissions

### Test Configuration

Create `terraform/tests/setup/.env` from the example:

```bash
cp terraform/tests/setup/env.example terraform/tests/setup/.env
# Edit with your Azure credentials
```

### CI Integration

Tests run automatically via GitHub Actions:
- **On PR**: Quick validation + module tests
- **Weekly**: Full test suite
- **Manual**: Via workflow_dispatch

---

## GitHub Actions Workflows

### Provision Workflow (`.github/workflows/provision.yaml`)

Main provisioning workflow triggered by `repository_dispatch`:

| Step | Description |
|------|-------------|
| Parse Request | Extract pattern request from payload |
| Resolve Patterns | Run `resolve-pattern.py` to generate tfvars |
| Terraform Init | Initialize with remote state backend |
| Terraform Apply | Apply infrastructure changes |
| Report Status | Update commit status and create issue |

### Deploy Portal (`.github/workflows/deploy-portal.yaml`)

Deploys the self-service portal:
- Generates portal data from pattern configs
- Embeds data in `web/index.html`
- Deploys to Azure Static Web Apps

### Deploy MCP Server (`.github/workflows/deploy-mcp-server.yaml`)

Deploys the MCP server:
- Builds Docker image
- Pushes to GitHub Container Registry
- Deploys to Azure Container Apps

### Terraform Tests (`.github/workflows/terraform-test.yaml`)

Runs the Terraform test suite:
- Quick validation on PRs
- Full suite on schedule and manual trigger
- Smart detection runs only tests for changed patterns/modules

### Pattern Release (`.github/workflows/release.yaml`)

Creates versioned releases for patterns:
- Triggered by git tags (`{pattern}/v{version}`)
- Validates tests pass for the pattern
- Generates changelog from commits
- Creates GitHub release with release notes
- Updates VERSION and CHANGELOG files

### Validate Pattern Sync (`.github/workflows/validate-module-sync.yaml`)

CI gate ensuring all generated files are in sync with `config/patterns/*.yaml`:
- JSON Schema (`schemas/infrastructure.yaml.json`)
- Portal PATTERNS_DATA (`web/index.html`)
- Workflow valid_patterns (`templates/infrastructure-workflow.yaml`)
- MCP patterns (`mcp-server/src/patterns.generated.json`)

**Triggers**: PRs/pushes affecting pattern files, or manually via workflow_dispatch.

**Fix sync issues**:
```bash
python3 scripts/generate-schema.py
```

---

## Security & RBAC

### Security Groups

Each pattern creates Entra ID security groups:

| Group | Purpose |
|-------|---------|
| `sg-{project}-{env}-{resource}-readers` | Read-only access |
| `sg-{project}-{env}-{resource}-admins` | Administrative access |

**Owner Delegation**: Pattern owners are set as group owners in Entra ID, allowing them to manage membership without platform intervention.

### RBAC Assignments

Patterns automatically assign Azure RBAC roles:

| Group | Role | Scope |
|-------|------|-------|
| Readers | Reader | Resource |
| Admins | Contributor or service-specific admin | Resource |

### Access Reviews (Production)

Production patterns include Entra ID access reviews:
- **Frequency**: Quarterly
- **Reviewers**: Group owners, then managers
- **Auto-apply**: Removes inactive members

### Required Permissions

#### Terraform Service Principal (Azure)

| Permission | Scope | Purpose |
|------------|-------|---------|
| Contributor | Subscription | Create resources |
| User Access Administrator | Subscription | Create RBAC assignments |
| Key Vault Secrets Officer | Key Vaults | Store secrets |

#### Terraform Service Principal (Microsoft Graph)

| Permission | Type | Purpose |
|------------|------|---------|
| Group.Create | Application | Create security groups |
| Group.Read.All | Application | Read group properties |
| User.Read.All | Application | Look up users by email |
| Application.Read.All | Application | Read application info |

#### GitHub App

| Permission | Access | Purpose |
|------------|--------|---------|
| contents | Read | Read infrastructure.yaml |
| statuses | Write | Update commit status |
| issues | Write | Create result issues |
| metadata | Read | Basic repo access |

---

## Generated Files (Single Source of Truth)

`config/patterns/*.yaml` is the **single source of truth** for pattern definitions. Several files are auto-generated from these pattern files to prevent drift:

| Generated File | Purpose |
|----------------|---------|
| `schemas/infrastructure.yaml.json` | JSON Schema for IDE validation (VS Code autocomplete) |
| `web/index.html` | Portal PATTERNS_DATA section |
| `templates/infrastructure-workflow.yaml` | valid_patterns list |
| `mcp-server/src/patterns.generated.json` | MCP server pattern data |

### Regenerating Files

After modifying any `config/patterns/*.yaml` file:

```bash
# Regenerate all derived files
python3 scripts/generate-schema.py

# Verify files are in sync
python3 scripts/generate-schema.py --check
```

CI will fail if generated files are out of sync. See the [Validate Pattern Sync](#validate-pattern-sync-githubworkflowsvalidate-module-syncyaml) workflow.

---

## Configuration Reference

### Repository Secrets (infrastructure-automation)

| Secret | Description |
|--------|-------------|
| `AZURE_TENANT_ID` | Azure tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `AZURE_CLIENT_ID_dev` | Service principal for dev |
| `AZURE_CLIENT_ID_staging` | Service principal for staging |
| `AZURE_CLIENT_ID_prod` | Service principal for prod |
| `TF_STATE_STORAGE_ACCOUNT` | Terraform state storage account |
| `TF_STATE_CONTAINER` | Terraform state container (default: tfstate) |
| `INFRA_APP_ID` | GitHub App ID |
| `INFRA_APP_PRIVATE_KEY` | GitHub App private key |

### Repository Secrets (consuming repos)

| Secret | Description |
|--------|-------------|
| `INFRA_APP_ID` | GitHub App ID |
| `INFRA_APP_PRIVATE_KEY` | GitHub App private key |

### Terraform State

State is stored in Azure Blob Storage with path:
```
{business_unit}/{environment}/{project}/{pattern}-{name}/terraform.tfstate
```

### Environment-Specific Credentials

Each environment uses a separate service principal for isolation:
- `AZURE_CLIENT_ID_dev` - Development environment
- `AZURE_CLIENT_ID_staging` - Staging environment
- `AZURE_CLIENT_ID_prod` - Production environment

---

## Troubleshooting

### Common Issues

#### Pattern Validation Failed

```
Error: Invalid pattern 'mypattern'
```

**Solution**: Check available patterns in `config/patterns/` or use the portal.

#### Terraform State Lock

```
Error: Error acquiring the state lock
```

**Solution**: Break the lease:
```bash
az storage blob lease break \
  --blob-name "{business_unit}/{environment}/{project}/{pattern}-{name}/terraform.tfstate" \
  --container-name tfstate \
  --account-name <storage_account>
```

#### Authorization Failed

```
Error: AuthorizationFailed - does not have authorization to perform action
```

**Solution**: Verify service principal has required roles (Contributor, User Access Administrator).

#### Security Group Creation Failed

```
Error: Insufficient privileges to complete the operation
```

**Solution**: Verify service principal has Microsoft Graph permissions (Group.Create, User.Read.All).

### Viewing Logs

```bash
# List recent workflow runs
gh run list --workflow=provision.yaml --limit 10

# View specific run logs
gh run view <run-id> --log

# View failed job logs only
gh run view <run-id> --log-failed
```

### Manual Provisioning

Trigger provisioning manually via workflow_dispatch:
```bash
gh workflow run provision.yaml \
  -f repository=owner/repo \
  -f commit_sha=abc123 \
  -f yaml_content="$(base64 < infrastructure.yaml)"
```

---

## Project Structure

```
infrastructure-automation/
├── .github/
│   └── workflows/
│       ├── provision.yaml          # Main provisioning workflow
│       ├── deploy-portal.yaml      # Portal deployment
│       ├── deploy-mcp-server.yaml  # MCP server deployment
│       ├── terraform-test.yaml     # Test suite
│       └── validate-module-sync.yaml # Sync validation
│
├── config/
│   ├── patterns/                   # Pattern metadata (14 YAML files)
│   │   ├── keyvault.yaml
│   │   ├── postgresql.yaml
│   │   ├── web-app.yaml
│   │   └── ...
│   └── sizing-defaults.yaml        # Default sizing configurations
│
├── examples/                       # Example pattern requests
│   ├── keyvault-pattern.yaml
│   ├── multi-pattern.yaml
│   ├── web-app-stack.yaml
│   └── ...
│
├── mcp-server/                     # MCP server for AI integration
│   ├── src/
│   │   ├── index.ts               # Main implementation
│   │   └── patterns.generated.json # Auto-generated pattern data
│   ├── package.json
│   └── Dockerfile
│
├── schemas/
│   └── infrastructure.yaml.json   # JSON Schema (auto-generated)
│
├── scripts/
│   ├── resolve-pattern.py         # Pattern resolution engine
│   ├── generate-schema.py         # Generates all derived files
│   └── create-release.sh          # Creates pattern releases
│
├── templates/
│   └── infrastructure-workflow.yaml # GitOps template for consuming repos
│
├── terraform/
│   ├── modules/                   # Shared Terraform modules (18)
│   │   ├── naming/
│   │   ├── security-groups/
│   │   ├── rbac-assignments/
│   │   ├── keyvault/
│   │   └── ...
│   │
│   ├── patterns/                  # Pattern Terraform configs (15)
│   │   ├── keyvault/
│   │   ├── web-app/
│   │   ├── api-backend/
│   │   └── ...
│   │
│   ├── platform/                  # Platform infrastructure
│   │   ├── portal/
│   │   └── state-storage/
│   │
│   ├── mcp-server/               # MCP server deployment
│   │
│   └── tests/                    # Testing framework
│       ├── run-tests.sh
│       ├── modules/              # Module tests (19)
│       └── patterns/             # Pattern tests (15)
│
├── web/
│   ├── index.html                # Self-service portal
│   └── staticwebapp.config.json
│
├── CLAUDE.md                     # Claude Code instructions
├── README.md                     # This file
└── infrastructure-platform-guide.md # Comprehensive platform guide
```

---

## Additional Documentation

- **[CLAUDE.md](CLAUDE.md)** - Instructions for Claude Code when working with this repository
- **[infrastructure-platform-guide.md](infrastructure-platform-guide.md)** - Comprehensive platform guide
- **[terraform/tests/README.md](terraform/tests/README.md)** - Testing framework documentation
- **[mcp-server/README.md](mcp-server/README.md)** - MCP server documentation

---

## License

Internal use only. Contact the Platform team for questions.
