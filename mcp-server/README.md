# Infrastructure MCP Server

An MCP (Model Context Protocol) server that enables AI assistants to analyze codebases and generate infrastructure configurations. Deployed on Azure Container Apps with API key authentication.

## Quick Start

### For Developers Using Claude Code

Add this to your project's `.mcp.json` file:

```json
{
  "mcpServers": {
    "infrastructure": {
      "type": "sse",
      "url": "https://ca-mcp-prod.mangoflower-3bcf53fc.centralus.azurecontainerapps.io/sse?api_key=YOUR_API_KEY"
    }
  }
}
```

Contact your platform team to get an API key.

### Getting the API Key (Platform Team)

```bash
# From Terraform state
cd terraform/mcp-server
terraform output -raw api_key

# Or from Azure directly
az containerapp secret show \
  --name ca-mcp-prod \
  --resource-group rg-mcp-prod \
  --secret-name api-key \
  --query value -o tsv
```

## Available Tools

Once connected, Claude Code can use these tools:

### `list_available_modules`

List all available Terraform modules with their configuration options.

```
Use list_available_modules to see what infrastructure I can provision
```

### `analyze_codebase`

Analyze a codebase to detect what infrastructure resources it needs. Scans for database connections, storage usage, frameworks, and environment variables.

> **⚠️ Important**: This tool only works in **local mode** (stdio). When using the hosted SSE server, the server cannot access your local filesystem. Use `analyze_files` instead.

```
Analyze my codebase at /path/to/project to determine what infrastructure it needs
```

### `analyze_files`

Analyze file contents to detect infrastructure needs. **Works with the remote SSE server** - Claude Code reads your local files and passes the contents to this tool for pattern analysis.

**Recommended files to include:**
- `package.json` or `requirements.txt` (dependencies)
- `host.json` (Azure Functions)
- `staticwebapp.config.json` (Static Web Apps)
- Source files with imports (database connections, SDK usage)

```
Read my package.json, host.json, and database.ts files, then use analyze_files to detect what infrastructure I need
```

### `generate_infrastructure_yaml`

Generate an `infrastructure.yaml` configuration file based on detected or specified resources.

```
Generate an infrastructure.yaml for my project with a PostgreSQL database and Key Vault
```

### `validate_infrastructure_yaml`

Validate an infrastructure configuration against the schema and available modules.

```
Validate this infrastructure.yaml file
```

### `get_module_details`

Get detailed information about a specific module including all config options and examples.

```
Show me the details for the postgresql module
```

### `generate_workflow`

Generate a GitHub Actions workflow file that processes `infrastructure.yaml` and triggers the provisioning pipeline. Save this in your repo as `.github/workflows/infrastructure.yaml`.

```
Generate a workflow file for my infrastructure provisioning
```

## Supported Resource Types

| Resource Type | Description | Key Options |
|--------------|-------------|-------------|
| `postgresql` | Azure Database for PostgreSQL Flexible Server | version, sku, storage_mb, backup_retention_days |
| `mongodb` | Azure Cosmos DB with MongoDB API | serverless, consistency_level, throughput |
| `keyvault` | Azure Key Vault for secrets and keys | sku, soft_delete_days, purge_protection, rbac_enabled |
| `storage_account` | Azure Storage Account | tier, replication, versioning, containers |
| `function_app` | Azure Functions | runtime, runtime_version, sku, app_settings |
| `eventhub` | Azure Event Hubs | sku, capacity, partition_count, message_retention |
| `aks_namespace` | Kubernetes namespace in shared AKS | cpu_limit, memory_limit, rbac_groups |
| `linux_vm` | Azure Linux Virtual Machine | size, image, os_disk_type, public_ip |
| `azure_sql` | Azure SQL Database | sku, version, databases, firewall_rules |
| `static_web_app` | Azure Static Web App | sku_tier |

## Module Management (Single Source of Truth)

The `MODULE_DEFINITIONS` object in `src/index.ts` serves as the **single source of truth** for all supported resource types. This ensures consistency between:

- The MCP server tools (`list_available_modules`, `analyze_files`, etc.)
- The `generate_workflow` tool output
- The GitOps workflow template (`templates/infrastructure-workflow.yaml`)

### How It Works

```
┌─────────────────────────────────────────┐
│  MODULE_DEFINITIONS (src/index.ts)      │  ◀── Single Source of Truth
└─────────────────────────────────────────┘
              │
              ▼
    ┌─────────────────────┐
    │ getValidResourceTypes() │
    └─────────────────────┘
              │
    ┌─────────┴─────────┐
    │                   │
    ▼                   ▼
┌─────────────┐   ┌─────────────────────────┐
│ MCP Tools   │   │ /schema/modules API     │
│ (runtime)   │   │ (for external sync)     │
└─────────────┘   └─────────────────────────┘
                            │
                            ▼
                  ┌─────────────────────────┐
                  │ sync-workflow-template.sh│
                  │ (updates template YAML) │
                  └─────────────────────────┘
```

### Adding a New Module

1. **Add the module definition** to `MODULE_DEFINITIONS` in `src/index.ts`:

```typescript
const MODULE_DEFINITIONS: Record<string, ModuleDefinition> = {
  // ... existing modules ...

  new_resource: {
    name: "new_resource",
    description: "Description of the new resource",
    required_fields: ["field1", "field2"],
    config_options: {
      option1: {
        type: "string",
        required: false,
        default: "default_value",
        description: "Description of option1"
      }
    },
    azure_resource: "Microsoft.ResourceType/resources",
    example: {
      type: "new_resource",
      name: "my-resource",
      config: {
        option1: "value"
      }
    }
  }
};
```

2. **Deploy the MCP server** - The CI/CD pipeline will build and deploy automatically on push to main.

3. **Sync the workflow template**:

```bash
# Automatically updates templates/infrastructure-workflow.yaml
./scripts/sync-workflow-template.sh

# Or specify a different MCP server URL
./scripts/sync-workflow-template.sh https://your-mcp-server.com
```

4. **Commit both changes** together to keep everything in sync.

### Schema API Endpoint

The MCP server exposes a public endpoint for fetching the current module schema:

```bash
curl https://ca-mcp-prod.mangoflower-3bcf53fc.centralus.azurecontainerapps.io/schema/modules
```

Response:
```json
{
  "valid_types": ["aks_namespace", "azure_sql", "eventhub", ...],
  "modules": {
    "postgresql": {
      "name": "postgresql",
      "description": "Azure Database for PostgreSQL Flexible Server",
      "config_options": ["version", "sku", "storage_mb", ...]
    }
  },
  "generated_at": "2026-01-19T12:00:00.000Z"
}
```

### CI Validation

The `.github/workflows/validate-module-sync.yaml` workflow automatically validates that `MODULE_DEFINITIONS` and the workflow template stay in sync:

- **Triggers**: On PRs or pushes that modify `mcp-server/src/index.ts` or `templates/infrastructure-workflow.yaml`
- **Action**: Extracts module names from both sources and compares them
- **On failure**: Shows which modules are missing and provides fix instructions

If the CI check fails:
```bash
# Option 1: Run the sync script
./scripts/sync-workflow-template.sh

# Option 2: Manually update the template
# Edit templates/infrastructure-workflow.yaml and update the valid_types list
```

## Architecture

```
┌─────────────────┐         ┌──────────────────────────┐
│  Claude Code    │◀──SSE──▶│  MCP Server              │
│  (Developer)    │         │  (Azure Container Apps)  │
└─────────────────┘         └──────────────────────────┘
        │                              │
        │                              ▼
        │                   ┌──────────────────────────┐
        │                   │  Codebase Analysis       │
        │                   │  Pattern Detection       │
        │                   │  YAML Generation         │
        │                   └──────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────┐
│  GitOps Workflow                                     │
│  CLI/API → Service Bus → GitHub Actions → Terraform │
└─────────────────────────────────────────────────────┘
```

## Authentication

The MCP server uses API key authentication:

- **SSE Endpoint**: Pass API key as query parameter: `/sse?api_key=YOUR_KEY`
- **Messages Endpoint**: API key is automatically included by the SSE transport

The API key is:
- Generated by Terraform using `random_password`
- Stored as a secret in Azure Container Apps
- Required for all connections (no anonymous access)

## API Endpoints

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/health` | GET | No | Health check (returns server status) |
| `/sse` | GET | Yes | SSE endpoint for MCP connections |
| `/messages` | POST | Yes | Message endpoint for MCP protocol |

## Local Development

### Running Locally (stdio mode)

```bash
cd mcp-server
npm install
npm run build
npm start
```

Configure Claude Code for local testing:
```json
{
  "mcpServers": {
    "infrastructure": {
      "command": "node",
      "args": ["/path/to/mcp-server/dist/index.js"]
    }
  }
}
```

### Running Locally (SSE mode)

```bash
# Without authentication
npm run start:sse

# With authentication
API_KEY=test-key npm run start:sse
```

Test the connection:
```bash
# Health check
curl http://localhost:3000/health

# SSE connection (without auth)
curl -N http://localhost:3000/sse

# SSE connection (with auth)
curl -N "http://localhost:3000/sse?api_key=test-key"
```

## Deployment

### Automatic Deployment (GitHub Actions)

The MCP server deploys automatically when:
- Changes are pushed to `main` branch in the `mcp-server/` directory
- Manual workflow dispatch via GitHub Actions

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_ID` | Azure AD app registration client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |

### Required GitHub Variables

| Variable | Description |
|----------|-------------|
| `TF_STATE_RESOURCE_GROUP` | Resource group containing Terraform state storage |
| `TF_STATE_STORAGE_ACCOUNT` | Storage account for Terraform state |
| `TF_STATE_CONTAINER` | Blob container for state files |

### Manual Deployment

```bash
# Build and push Docker image
cd mcp-server
docker build -t ghcr.io/your-org/infrastructure-mcp-server:latest .
docker push ghcr.io/your-org/infrastructure-mcp-server:latest

# Deploy with Terraform
cd ../terraform/mcp-server
terraform init \
  -backend-config="resource_group_name=your-rg" \
  -backend-config="storage_account_name=yourstorageaccount" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=mcp/prod/terraform.tfstate"

terraform apply -var="container_registry=ghcr.io/your-org"

# Get the API key
terraform output -raw api_key
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MCP_TRANSPORT` | `stdio` | Transport mode: `stdio` or `sse` |
| `PORT` | `3000` | HTTP port for SSE mode |
| `NODE_ENV` | `development` | Node environment |
| `API_KEY` | (none) | API key for authentication (SSE mode only) |

## Troubleshooting

### "Session not found" error

This was fixed in the current version. If you see this error, ensure you're running the latest image:

```bash
az containerapp update --name ca-mcp-prod --resource-group rg-mcp-prod \
  --image "ghcr.io/your-org/infrastructure-mcp-server:latest" \
  --revision-suffix "v$(date +%s)"
```

### Connection closes immediately

Check that:
1. The API key is correct
2. The URL includes the `?api_key=` parameter
3. The container is healthy: `curl https://your-server/health`

### Tools not appearing in Claude Code

1. Restart Claude Code after adding `.mcp.json`
2. Check the MCP server status in Claude Code settings
3. Verify the SSE connection with curl:
   ```bash
   curl -N "https://your-server/sse?api_key=YOUR_KEY"
   ```

## Cost

Azure Container Apps with scale-to-zero:
- **Idle**: ~$0/month (scales to 0 when not in use)
- **Active**: ~$0.000024/vCPU-second + $0.000003/GiB-second
- **Typical usage**: $1-5/month for light usage

## Security Notes

- API keys should be rotated periodically
- Use project-specific `.mcp.json` files (not global)
- The `.mcp.json` file may contain secrets - add to `.gitignore` if needed
- Consider using Azure Key Vault for API key management in production
