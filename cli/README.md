# Infrastructure Self-Service CLI

A command-line tool for requesting and managing Azure infrastructure resources.

## Installation

```bash
cd cli
pip install -e .
```

## Configuration

Set environment variables:

```bash
export INFRA_API_URL="https://your-function-app.azurewebsites.net"
export INFRA_API_KEY="your-api-key"
```

## Usage

### Initialize a new configuration

```bash
infra init web-app-stack -o my-app.yaml
```

### Submit a provisioning request

```bash
infra provision my-app.yaml --email your@email.com
```

### Check request status

```bash
infra status <request-id>
```

### List available templates

```bash
infra templates
```

### Dry run (validate without submitting)

```bash
infra provision my-app.yaml --email your@email.com --dry-run
```

## YAML Configuration Format

```yaml
metadata:
  project_name: my-web-app
  environment: dev          # dev, staging, prod
  business_unit: engineering
  cost_center: CC-1234
  owner_email: owner@company.com

resources:
  - type: postgresql
    name: main-db
    config:
      sku: B_Standard_B1ms
      storage_mb: 32768

  - type: storage_account
    name: data
    config:
      tier: Standard
      replication: LRS
      containers:
        - name: uploads
```

## Available Resource Types

- `postgresql` - Azure Database for PostgreSQL Flexible Server
- `mongodb` - Azure Cosmos DB with MongoDB API
- `keyvault` - Azure Key Vault
- `storage_account` - Azure Storage Account
- `eventhub` - Azure Event Hubs
- `function_app` - Azure Functions
- `linux_vm` - Azure Linux Virtual Machine
- `aks_namespace` - AKS Namespace with RBAC
