# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Enterprise Infrastructure Self-Service Platform: A catalog-driven, multi-tenant infrastructure provisioning system that allows teams to request cloud resources via CLI, REST API, or web portal. Uses event-driven architecture with Azure Functions, Service Bus, Cosmos DB, and GitHub Actions for Terraform execution.

## Common Commands

### CLI Development
```bash
cd cli
pip install -e .                              # Install CLI in dev mode
infra provision <file.yaml> --email <email>   # Submit request
infra status <request-id>                     # Check status
```

### API Gateway (Local Testing)
```bash
cd infrastructure/api-gateway
pip install -r requirements.txt
func start                                    # Start locally
```

### Terraform
```bash
cd terraform/catalog
terraform init
terraform plan -var="config_file=../config.yaml"
terraform apply -auto-approve tfplan
```

### Full Platform Deployment
```bash
bash scripts/deploy-platform.sh    # Requires: ARM_SUBSCRIPTION_ID, ARM_TENANT_ID, GH_PAT
```

## Architecture

### Request Processing Flow
```
CLI/API → Azure Functions API Gateway → Service Bus Queues (prod/staging/dev)
→ GitHub Actions Queue Consumer (cron: every minute)
→ Provision Worker (parallel: up to 10 workers)
→ Terraform Apply → Azure Resources + Cosmos DB state tracking
```

### Key Components

1. **CLI** (`cli/infra_cli.py`) - Click-based Python CLI that submits YAML configs to API Gateway

2. **API Gateway** (`infrastructure/api-gateway/function_app.py`) - Azure Functions HTTP API that:
   - Validates YAML schema and policy (cost limits per environment)
   - Estimates infrastructure costs
   - Stores requests in Cosmos DB (partitioned by `requestId`)
   - Queues to Service Bus with environment-based priority

3. **Queue Consumer** (`.github/workflows/queue-consumer.yaml`) - Scheduled workflow that polls three Service Bus queues and dispatches to provision workers

4. **Provision Worker** (`.github/workflows/provision-worker.yaml`) - Reusable workflow that:
   - Updates Cosmos DB status to "processing"
   - Generates and applies Terraform configs
   - Captures outputs and marks completion

5. **Terraform Catalog** (`terraform/catalog/main.tf`) - Dynamic resource provisioning using YAML-driven for-each patterns. Supports: PostgreSQL, MongoDB, Key Vault, Storage Account, VMs, AKS namespaces, Function Apps, Event Hubs

6. **Terraform Modules** (`terraform/modules/`) - Reusable modules for each resource type

### Environment Separation
- Three Service Bus queues with priority: prod > staging > dev
- Cost limits enforced: prod ($10k), staging ($2k), dev ($500)
- Separate Terraform state per business-unit/environment/project in Azure Storage
- OIDC-based authentication for GitHub Actions runners

### Multi-Tenancy
- Business unit isolation via resource groups (pattern: `rg-{project}-{environment}`)
- State path: `{business_unit}/{environment}/{project}/terraform.tfstate`
- RBAC per business unit with metadata tagging for billing

## Configuration

### Required Environment Variables

**API Gateway:**
- `SERVICEBUS_CONNECTION` - Service Bus connection string
- `COSMOS_DB_ENDPOINT` - Cosmos DB endpoint URL
- `COSMOS_DB_KEY` - Cosmos DB access key

**CLI:**
- `INFRA_API_URL` - API Gateway base URL
- `INFRA_API_KEY` - API authentication key

**Terraform State:**
- `TF_STATE_STORAGE_ACCOUNT` - Azure Storage account for state
- `TF_STATE_CONTAINER` - Blob container name

### YAML Request Format
See `examples/` directory for templates. Basic structure:
```yaml
metadata:
  project: my-project
  environment: dev
  business_unit: engineering
  owner: team@example.com
resources:
  - type: postgresql
    name: mydb
    sku: B_Standard_B1ms
```

## Error Handling Patterns

- Failed Service Bus messages go to DLQ for retry
- Failed requests marked as "failed" in Cosmos DB with error details
- Policy violations return 403 with specific violation message
- Schema validation errors return 400 with field-level details

## Key Documentation

- `infrastructure-platform-guide.md` - Comprehensive platform guide
- `docs/ARCHITECTURE.md` - System design diagrams
- `docs/LOCAL-K8S-SETUP.md` - Local k3s cluster setup for self-hosted runners
