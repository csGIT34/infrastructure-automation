# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

Infrastructure Self-Service Platform with a 5-layer architecture. Developers interact through an MCP server via Claude Code to provision Azure resources using opinionated patterns.

- **Budget target:** Under $50/month
- **Single Azure subscription**, dev/prod simulated via resource groups
- **Two provisioning modes:**
  - **Prototype:** MCP server triggers GitHub Actions `workflow_dispatch` directly
  - **Production:** MCP server pushes tfvars to `app-infrastructure` repo (GitOps, branch-per-app-environment)

## Architecture

```
Developer (Claude Code)
  -> MCP Server (Python, Azure Container App)
     -> Prototype: triggers GitHub Actions workflow_dispatch
     -> Production: pushes tfvars to app-infrastructure repo
        -> Branch: {app}/{env} (e.g., myapp/dev, myapp/prod)
        -> Push triggers terraform apply workflow
```

## Common Commands

### Terraform
```bash
# Validate a module
cd terraform/modules/key_vault && terraform init -backend=false && terraform validate

# Validate a pattern
cd terraform/patterns/key_vault && terraform init -backend=false && terraform validate
```

### MCP Server
```bash
# Install dependencies
cd mcp-server && pip install -e .

# Run locally (stdio mode for Claude Code)
cd mcp-server && MCP_TRANSPORT=stdio python -m src.server

# Run locally (HTTP mode)
cd mcp-server && python -m src.server
```

### Pattern Resolution (reference script)
```bash
python3 scripts/resolve-pattern.py --list-patterns
```

## Directory Structure

```
.github/workflows/
  terraform-test.yaml          # Validate modules/patterns on PR
  prototype-provision.yaml     # workflow_dispatch triggered by MCP server
  deploy-mcp-server.yaml       # Build and deploy MCP server container
  release.yaml                 # Tag-triggered pattern releases
  validate-module-sync.yaml    # Ensure config/ and terraform/ are in sync

terraform/
  modules/                     # Bare-bones Azure resource modules
    resource_group/             # azurerm_resource_group
    key_vault/                  # azurerm_key_vault + secrets
    storage_account/            # azurerm_storage_account + containers
    postgresql/                 # azurerm_postgresql_flexible_server + database
    container_app/              # azurerm_container_app + environment
    naming/                     # Resource naming conventions (cross-cutting)
    security_groups/            # Entra ID groups (cross-cutting)
    rbac_assignments/           # Azure RBAC (cross-cutting)
    diagnostic_settings/        # Azure Monitor (cross-cutting)
  patterns/                     # Compositions of modules
    key_vault/                  # Key Vault + security + RBAC + diagnostics
    storage_account/            # Storage + security + RBAC + diagnostics
    postgresql/                 # PostgreSQL + Key Vault + security + RBAC
    container_app/              # Container App + security + RBAC + diagnostics
    web_backend/                # Container App + PostgreSQL + Key Vault (composite)

config/patterns/                # Pattern definitions (YAML, source of truth)
  key_vault.yaml
  storage_account.yaml
  postgresql.yaml
  container_app.yaml
  web_backend.yaml

mcp-server/                     # Python MCP server (FastMCP)
  src/
    server.py                   # FastMCP entry point with all tools
    auth/
      __init__.py
      provider.py               # EntraOAuthProvider (Entra ID OAuth proxy)
    tools/                      # Tool implementations
      patterns.py               # list_patterns, get_pattern_details, estimate_cost
      provision.py              # provision, destroy (prototype mode)
      tfvars.py                 # push_tfvars (production mode)
      status.py                 # check_status, list_deployments
    patterns/
      loader.py                 # Load config/patterns/*.yaml
      resolver.py               # Resolve config to tfvars
    github/
      client.py                 # GitHub API (trigger workflows, push files)
  pyproject.toml
  Dockerfile

app-infrastructure/             # Reference for the GitOps repo
  .github/workflows/
    terraform-apply.yaml        # Apply on push to {app}/{env} branches

scripts/resolve-pattern.py      # Reference pattern resolver (ported to MCP server)
```

## Available Patterns

| Pattern | Category | Description |
|---------|----------|-------------|
| `key_vault` | single | Key Vault with security groups, RBAC |
| `storage_account` | single | Storage Account with containers |
| `postgresql` | single | PostgreSQL with Key Vault for secrets |
| `container_app` | single | Container App with environment |
| `web_backend` | composite | Container App + PostgreSQL + Key Vault |

## MCP Server Tools

| Tool | Description |
|------|-------------|
| `list_patterns` | List available patterns with filtering |
| `get_pattern_details` | Sizing, config options, cost for a pattern |
| `estimate_cost` | Monthly cost estimate for a configuration |
| `validate_config` | Validate config before provisioning |
| `provision` | Prototype: trigger GH Actions to create resources |
| `destroy` | Prototype: trigger GH Actions to destroy resources |
| `push_tfvars` | Production: push tfvars to app-infrastructure repo |
| `check_status` | Check workflow run status |
| `list_deployments` | List active deployments |

## Adding New Patterns

1. Create `config/patterns/<name>.yaml` (source of truth)
2. Create `terraform/modules/<name>/` with `main.tf`, `variables.tf`, `outputs.tf`
3. Create `terraform/patterns/<name>/` with `main.tf`, `variables.tf`, `outputs.tf`, `VERSION`
4. MCP server auto-discovers patterns from `config/patterns/`

## Authentication

The MCP server is secured with Entra ID OAuth when deployed remotely. Auth is **conditionally enabled** — only when `AZURE_TENANT_ID`, `MCP_ENTRA_CLIENT_ID`, and `MCP_SERVER_URL` env vars are set. Local stdio mode has no auth.

**Flow:** Claude Code → MCP `/authorize` → Entra ID login → `/auth/callback` → Claude Code

- **App Registration:** `Infrastructure MCP Server` (Web platform, confidential client + PKCE)
- **Client ID:** `ff976387-aa84-43d3-a075-c8e292bb715c`
- MCP server issues its own JWT access tokens (RSA-signed, 1hr lifetime, in-memory)
- Dynamic Client Registration enabled for Claude Code auto-registration
- Container restart clears all tokens (users re-auth via browser)

## Required Secrets

**Azure:** `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID_dev/staging/prod`
**Terraform State:** `TF_STATE_STORAGE_ACCOUNT`, `TF_STATE_CONTAINER`, `TF_STATE_RESOURCE_GROUP`
**GitHub App:** `INFRA_APP_ID`, `INFRA_APP_PRIVATE_KEY`
**Entra ID Auth:** `MCP_ENTRA_CLIENT_SECRET`

## Required Variables

**Entra ID Auth:** `MCP_ENTRA_CLIENT_ID`

## T-Shirt Sizing

| Size | Dev | Staging | Prod |
|------|-----|---------|------|
| small | Minimal | Basic | Production-ready |
| medium | Basic | Production-ready | High performance |
| large | Production-ready | High performance | Enterprise scale |

Default: dev=small, staging=medium, prod=medium
