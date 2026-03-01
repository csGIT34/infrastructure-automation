# Infrastructure Self-Service Platform

A simplified infrastructure provisioning platform where developers request Azure resources through Claude Code via an MCP server. Resources are provisioned using opinionated patterns that bundle base resources with security groups, RBAC, and optional diagnostics.

## Quick Start

### For Developers (via Claude Code)

With the MCP server configured in `.mcp.json`, use natural language:

> "Provision a Key Vault called myapp-secrets in dev for the billing team"

Claude Code uses MCP tools to:
1. Validate the configuration
2. Estimate costs
3. Trigger provisioning

### Available Patterns

| Pattern | Description | Dev Cost |
|---------|-------------|----------|
| `key_vault` | Key Vault with RBAC | ~$1/mo |
| `storage_account` | Storage with containers | ~$2/mo |
| `postgresql` | PostgreSQL + Key Vault for secrets | ~$15/mo |
| `container_app` | Container App with HTTP ingress | ~$0/mo |
| `web_backend` | Container App + PostgreSQL + Key Vault | ~$16/mo |

## Architecture

```
Developer (Claude Code)
  -> MCP Server (Python, Azure Container App)
     -> Prototype: triggers GitHub Actions workflow_dispatch
     -> Production: pushes tfvars to app-infrastructure repo
```

### Two Provisioning Modes

**Prototype (direct):** MCP server triggers `prototype-provision.yaml` workflow via `workflow_dispatch`. Resources are created immediately.

**Production (GitOps):** MCP server pushes `terraform.tfvars.json` to a branch in the `app-infrastructure` repo. Push triggers `terraform-apply.yaml` workflow. Branch format: `{app}/{env}`.

### 5-Layer Architecture

1. **MCP Server** - Python FastMCP server with tools for pattern discovery, validation, and provisioning
2. **Patterns** - Opinionated compositions that bundle modules with security and RBAC
3. **Modules** - Bare-bones Azure resource wrappers with typed variables
4. **Workflows** - GitHub Actions for terraform plan/apply
5. **State** - Azure Storage backend with per-deployment state isolation

## Project Structure

```
terraform/modules/          # 9 modules (5 resource + 4 cross-cutting)
terraform/patterns/         # 5 patterns (4 single + 1 composite)
config/patterns/            # Pattern definitions (source of truth)
mcp-server/                 # Python MCP server
.github/workflows/          # CI/CD workflows
app-infrastructure/         # GitOps repo reference
```

## Setup

### Required Secrets

| Secret | Purpose |
|--------|---------|
| `AZURE_TENANT_ID` | Azure tenant |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription |
| `AZURE_CLIENT_ID_dev/staging/prod` | Service principals (OIDC) |
| `TF_STATE_STORAGE_ACCOUNT` | Terraform state storage |
| `INFRA_APP_ID` | GitHub App for cross-repo operations |
| `INFRA_APP_PRIVATE_KEY` | GitHub App private key |

### Running the MCP Server Locally

```bash
cd mcp-server
pip install -e .
MCP_TRANSPORT=stdio python -m src.server
```

## Adding a New Pattern

1. Create `config/patterns/<name>.yaml` with sizing, config, and cost estimates
2. Create `terraform/modules/<name>/` with the base Azure resource
3. Create `terraform/patterns/<name>/` composing modules with security and RBAC
4. The MCP server auto-discovers new patterns from `config/patterns/`
