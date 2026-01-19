# Infrastructure Self-Service CLI

Command-line tool for requesting and managing Azure infrastructure resources.

## Installation

### Using uv (recommended)

```bash
# Install as a tool (globally available)
uv tool install git+https://github.com/csGIT34/infrastructure-automation.git#subdirectory=cli

# Or add to a project
uv add git+https://github.com/csGIT34/infrastructure-automation.git#subdirectory=cli
```

### Using pip

```bash
pip install git+https://github.com/csGIT34/infrastructure-automation.git#subdirectory=cli
```

### Development install

```bash
cd cli
uv pip install -e .
```

## Configuration

Set environment variables:

```bash
export INFRA_API_URL="https://func-infra-api.azurewebsites.net"
export INFRA_API_KEY="your-api-key"
```

## Quick Start

```bash
# Browse available patterns
infra patterns list

# Create config interactively
infra init -i

# Submit request
infra provision infrastructure.yaml --email your@email.com
```

## Usage

### Browse patterns

```bash
infra patterns list
infra patterns show web-app
```

### Create infrastructure config (interactive wizard)

```bash
infra init -i
```

### Create infrastructure config (command line)

```bash
infra init --pattern web-app --env dev \
  --project my-app \
  --business-unit engineering \
  --cost-center CC-1234 \
  --email team@example.com
```

### Submit a provisioning request

```bash
infra provision my-app.yaml --email your@email.com

# Dry run first (validate without submitting)
infra provision my-app.yaml --email your@email.com --dry-run
```

### Check request status

```bash
infra status <request-id>
```

## Available Patterns

| Pattern | Description | Dev Cost |
|---------|-------------|----------|
| `web-app` | Full-stack with Function App + SQL + Storage | $0/month |
| `api-backend` | Serverless API with Function App + Key Vault | $0/month |
| `data-pipeline` | Event Hub + Functions + Storage | ~$25/month |
| `static-site` | Static Web App hosting | $0/month |

## Available Resource Types

- `azure_sql` - Azure SQL Database
- `function_app` - Azure Functions
- `storage_account` - Azure Storage Account
- `keyvault` - Azure Key Vault
- `eventhub` - Azure Event Hubs
- `static_web_app` - Azure Static Web Apps
- `postgresql` - Azure Database for PostgreSQL
- `mongodb` - Azure Cosmos DB with MongoDB API
- `linux_vm` - Azure Linux Virtual Machine
- `aks_namespace` - AKS Namespace with RBAC

## YAML Configuration Format

```yaml
metadata:
  project_name: my-web-app
  environment: dev          # dev, staging, prod
  business_unit: engineering
  cost_center: CC-1234
  owner_email: owner@company.com

resources:
  - type: function_app
    name: api
    config:
      runtime: python
      runtime_version: "3.11"
      sku: Y1              # Y1 = free consumption plan

  - type: azure_sql
    name: db
    config:
      sku: Free            # Free tier available
      databases:
        - name: appdb
          sku: Free
```
