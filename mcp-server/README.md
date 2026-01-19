# Infrastructure MCP Server

An MCP (Model Context Protocol) server that enables AI assistants to generate infrastructure patterns and Terraform configurations on-the-fly.

## Features

- **Pattern Generation**: Create YAML infrastructure patterns from natural language descriptions
- **Terraform Generation**: Generate ready-to-apply Terraform configurations
- **Module Discovery**: List available infrastructure modules and their configurations
- **Pattern Browsing**: View existing patterns for reference
- **Cost Estimation**: Estimate infrastructure costs before provisioning

## Supported Resource Types

| Resource Type | Description | Key Options |
|--------------|-------------|-------------|
| `postgresql` | Azure Database for PostgreSQL | sku, storage_mb, version, backup, geo_redundancy |
| `mongodb` | Azure Cosmos DB (MongoDB API) | throughput, consistency, geo_redundancy, backup |
| `keyvault` | Azure Key Vault | sku, soft_delete, purge_protection, rbac |
| `storage` | Azure Storage Account | tier, replication, blob_versioning, containers |
| `function_app` | Azure Functions | runtime, version, sku, always_on |
| `eventhub` | Azure Event Hubs | sku, capacity, partitions, retention, capture |
| `aks_namespace` | AKS Kubernetes Namespace | cpu_limit, memory_limit, rbac, network_policies |
| `linux_vm` | Azure Linux Virtual Machine | size, os, disk_size, admin_username |

## Usage

### Local Development (stdio mode)

```bash
cd mcp-server
npm install
npm run build
npm start
```

Configure in Claude Code settings:
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

### Remote Server (SSE mode)

Start locally for testing:
```bash
npm run start:sse
```

Or use the hosted version (after deployment):
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

## MCP Tools

### generate_pattern

Generate an infrastructure pattern from a description.

**Parameters:**
- `description` (required): What infrastructure you need
- `project` (required): Project name
- `environment` (required): Environment (dev/staging/prod)
- `business_unit` (required): Business unit name
- `owner` (required): Owner email address

**Example:**
```
Generate a pattern for a PostgreSQL database with 50GB storage for the analytics team
```

### generate_terraform

Generate Terraform configuration from a YAML pattern.

**Parameters:**
- `pattern_yaml` (required): The YAML pattern content

### list_modules

List all available infrastructure modules with their configuration options.

### list_patterns

List existing patterns in the patterns directory.

### estimate_cost

Estimate the monthly cost for infrastructure.

**Parameters:**
- `pattern_yaml` (required): The YAML pattern content

## Deployment

### Prerequisites

- Azure subscription with Container Apps enabled
- GitHub repository with GHCR access
- Terraform state backend configured

### GitHub Actions Deployment

The deployment workflow triggers on:
- Push to `main` branch with changes in `mcp-server/`
- Manual workflow dispatch

Required secrets:
- `AZURE_CLIENT_ID`: Azure service principal client ID
- `AZURE_TENANT_ID`: Azure tenant ID
- `AZURE_SUBSCRIPTION_ID`: Azure subscription ID

Required variables:
- `TF_STATE_RESOURCE_GROUP`: Resource group for Terraform state
- `TF_STATE_STORAGE_ACCOUNT`: Storage account for Terraform state
- `TF_STATE_CONTAINER`: Blob container for Terraform state

### Manual Deployment

```bash
# Build and push image
docker build -t ghcr.io/your-org/infrastructure-mcp-server:latest ./mcp-server
docker push ghcr.io/your-org/infrastructure-mcp-server:latest

# Deploy with Terraform
cd terraform/mcp-server
terraform init
terraform apply \
  -var="container_registry=ghcr.io/your-org" \
  -var="image_tag=latest"
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/sse` | GET | SSE endpoint for MCP connections |
| `/messages` | POST | Message endpoint for SSE transport |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MCP_TRANSPORT` | `stdio` | Transport mode: `stdio` or `sse` |
| `PORT` | `3000` | HTTP port for SSE mode |
| `NODE_ENV` | `development` | Node environment |

## Development

```bash
# Install dependencies
npm install

# Build TypeScript
npm run build

# Run in stdio mode
npm run dev

# Run in SSE mode
npm run dev:sse
```

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Claude Code    │────▶│  MCP Server      │────▶│  Pattern Files  │
│  (AI Assistant) │ SSE │  (Container App) │     │  (Local/Remote) │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                               │
                               ▼
                        ┌──────────────────┐
                        │  Terraform       │
                        │  Generation      │
                        └──────────────────┘
```
