# Infrastructure Self-Service Platform

Enterprise cloud platform on Azure with hub-spoke architecture. Developers provision Azure resources through Claude Code via an MCP server using approved infrastructure patterns. Resources are bundled with security groups, RBAC, and enterprise tagging.

## Quick Start

With the MCP server configured in `.mcp.json`, use natural language:

> "Provision a Key Vault called myapp-secrets in dev for the billing team"

Claude Code uses MCP tools to validate the configuration and trigger provisioning.

## Available Patterns

| Pattern | Category | Description |
|---------|----------|-------------|
| `key_vault` | single | Key Vault with RBAC and security groups |
| `postgresql` | single | PostgreSQL + Key Vault for secrets |
| `container_app` | single | Container App with HTTP ingress |
| `container_registry` | single | Container Registry with RBAC |
| `web_backend` | composite | Container App + PostgreSQL + Key Vault + ACR |

## Architecture

```
Developer (Claude Code)
  -> MCP Server (Python FastMCP, Azure Container App)
     -> provision tool: pushes tfvars to app-infrastructure (prototype env only)
     -> destroy tool: triggers workflow_dispatch for terraform destroy (prototype only)
     -> push_tfvars tool: DevOps pushes tfvars for non-prototype envs

All tfvars stored in app-infrastructure: {app_id}/{app_name}/{environment}/{pattern}/
Push to main triggers terraform-apply.yaml (folder-based GitOps)
ArgoCD manages all Kubernetes changes

Promotion (DevOps):
  promote.yaml workflow_dispatch → copies tfvars, adjusts sizing → creates PR
  PR merge → terraform-apply.yaml → deploys to target environment
```

## Environments

| Environment | Purpose | Default Size |
|-------------|---------|-------------|
| `prototype` | Developer self-service sandbox | small |
| `dev` | Development integration | small |
| `tst` | Testing/QA | small |
| `stg` | Staging/pre-prod | medium |
| `prd` | Production | medium |

## Promotion Flow

PR-based promotion between environments. Not all apps move beyond prototype — it's a stable state.

```
PROTOTYPE  Developer self-service via MCP provision tool
           {app_id}/{app_name}/prototype/{pattern}/
              │
              ▼  (promote.yaml → PR)
DEV        {app_id}/{app_name}/dev/{pattern}/
           Size: small, Tier 4 defaults
              │
              ▼  (promote.yaml → PR)
TST        {app_id}/{app_name}/tst/{pattern}/
           Size: small, QA/testing
              │
              ▼  (promote.yaml → PR)
STG        {app_id}/{app_name}/stg/{pattern}/
           Size: medium, Tier-appropriate defaults
              │
              ▼  (promote.yaml → PR)
PRD        {app_id}/{app_name}/prd/{pattern}/
           Size: medium/large, HA/DR, geo-redundant backups
```

### How Promotion Works

1. **Prototype** — Developer uses `provision` MCP tool. Tfvars pushed to app-infrastructure under the `prototype` folder. Terraform apply runs automatically.
2. **Promote** — DevOps triggers `promote.yaml` from GitHub Actions UI. Workflow reads source tfvars, adjusts sizing for the target environment, and creates a PR.
3. **Review & Merge** — DevOps reviews sizing changes in the PR. Merging triggers `terraform-apply.yaml` for the target environment.
4. **Repeat** — Promote through dev → tst → stg → prd as needed.

Each environment gets its own Terraform state, Azure service principal (OIDC), and environment-specific sizing.

## Application Tiers

Tier assignment drives redundancy, backup frequency, monitoring sensitivity, failover configuration, and SLA targets.

| Tier | Priority | RTO | HA/DR | Description |
|------|----------|-----|-------|-------------|
| 1 | Highest | 4 hours | Cross-region HA/DR | Mission-critical, always available |
| 2 | High | 8 hours | Single-region HA | Business-critical with redundancy |
| 3 | Medium | 24 hours | Backup/restore | Standard workloads |
| 4 | Low | 72 hours | Best-effort | Non-critical, dev/test |

## T-Shirt Sizing

Each pattern defines size-specific configurations per environment. Default sizes are applied per environment when not explicitly set.

| Size | Use Case | Default For |
|------|----------|-------------|
| S (small) | Dev/test, minimal resources | `prototype`, `dev`, `tst` |
| M (medium) | Standard workloads, moderate traffic | `stg`, `prd` |
| L (large) | High-traffic, production workloads | — |
| XL (xlarge) | Enterprise-scale, high-performance | — |

## Repository Strategy

Each Terraform module and pattern lives in its own repository for independent versioning and reusability. This repo (`infrastructure-automation`) is the orchestration hub.

| Repository | Type | Description |
|------------|------|-------------|
| `infrastructure-automation` | Orchestration | MCP server, workflows, pattern YAMLs |
| `app-infrastructure` | GitOps | Folder-based tfvars, triggers terraform apply |
| `terraform-azurerm-key-vault` | Module | Key Vault resource module |
| `terraform-azurerm-postgresql` | Module | PostgreSQL Flexible Server module |
| `terraform-azurerm-container-app` | Module | Container App + Environment module |
| `terraform-azurerm-container-registry` | Module | Container Registry module |
| `terraform-azurerm-naming` | Module | Cross-cutting naming conventions |
| `terraform-azurerm-security-groups` | Module | Cross-cutting Entra ID groups |
| `terraform-azurerm-rbac-assignments` | Module | Cross-cutting Azure RBAC |
| `terraform-azurerm-resource-group` | Module | Resource Group module |
| `terraform-pattern-web-backend` | Pattern | Composite: Container App + PostgreSQL + Key Vault + ACR |

## Enterprise Tagging

All resources must include these tags:

| Tag | Description |
|-----|-------------|
| `application_id` | Unique application identifier |
| `application_name` | Human-readable application name |
| `environment` | prototype / dev / tst / stg / prd |
| `business_unit` | Owning business unit |
| `tier` | Application tier (1-4) |
| `cost_center` | Billing cost center |
| `managed_by` | `terraform` |

## Project Structure

```
.github/workflows/
  terraform-test.yaml          # Validate modules/patterns on PR
  prototype-provision.yaml     # workflow_dispatch triggered by MCP server
  deploy-mcp-server.yaml       # Build and deploy MCP server container
  validate-module-sync.yaml    # Ensure config/ and terraform/ are in sync

terraform/
  modules/                     # Reference implementations (split into separate repos)
    resource_group/
    key_vault/
    postgresql/
    container_app/
    naming/                     # Cross-cutting: naming conventions
    security_groups/            # Cross-cutting: Entra ID groups
    rbac_assignments/           # Cross-cutting: Azure RBAC
  patterns/                     # Reference implementations (split into separate repos)
    key_vault/
    postgresql/
    container_app/
    web_backend/

config/patterns/                # Pattern definitions (YAML, source of truth)
  key_vault.yaml
  postgresql.yaml
  container_app.yaml
  container_registry.yaml
  web_backend.yaml

mcp-server/                     # Python MCP server (FastMCP)
  src/
    server.py                   # FastMCP entry point
    auth/                       # Entra ID OAuth
    tools/                      # Tool implementations
    patterns/                   # Pattern loading and resolution
    github/                     # GitHub API client

app-infrastructure/             # Reference for the GitOps repo
  .github/workflows/
    terraform-apply.yaml        # Apply on push to main (folder-based)
    promote.yaml                # PR-based environment promotion
```

## Setup

### Required Secrets

| Secret | Purpose |
|--------|---------|
| `AZURE_TENANT_ID` | Azure tenant |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription |
| `AZURE_CLIENT_ID_prototype/dev/tst/stg/prd` | Service principals (OIDC) |
| `TF_STATE_STORAGE_ACCOUNT` | Terraform state storage |
| `INFRA_APP_ID` | GitHub App for cross-repo operations |
| `INFRA_APP_PRIVATE_KEY` | GitHub App private key |
| `MCP_ENTRA_CLIENT_SECRET` | Entra ID auth (remote deployment) |

### MCP Server Environment Variables

| Variable | Purpose | Example |
|----------|---------|---------|
| `INFRA_REPO` | Infrastructure-automation repo | `AzSkyLab/infrastructure-automation` |
| `APP_INFRA_REPO` | App-infrastructure GitOps repo | `AzSkyLab/app-infrastructure` |
| `INFRA_APP_ID` | GitHub App ID for API auth | |
| `INFRA_APP_PRIVATE_KEY` | GitHub App private key (PEM) | |
| `MCP_TRANSPORT` | Transport mode (`streamable-http` or `stdio`) | `streamable-http` |
| `MCP_HOST` | Bind address (default: `127.0.0.1`) | `0.0.0.0` |
| `MCP_PORT` | Listen port (default: `8000`) | `8000` |

### Running Locally

```bash
cd mcp-server
pip install -e .
export INFRA_REPO=AzSkyLab/infrastructure-automation
export APP_INFRA_REPO=AzSkyLab/app-infrastructure
MCP_TRANSPORT=stdio python -m src.server
```

## Adding a New Pattern

1. Create `config/patterns/<name>.yaml` with sizing, tier defaults, and config options
2. Create module repo `terraform-azurerm-<resource>` with `main.tf`, `variables.tf`, `outputs.tf`
3. For composite patterns, create pattern repo `terraform-pattern-<name>`
4. The MCP server auto-discovers patterns from `config/patterns/`
5. Include tier-appropriate defaults for redundancy, backup, and recovery
6. Add the pattern to `terraform-apply.yaml` composite list if it's a composite pattern
