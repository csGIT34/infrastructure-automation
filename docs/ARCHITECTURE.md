# Architecture Overview

## System Components

### 1. Developer Interfaces
- **Web Portal** - Self-service UI for infrastructure requests
- **CLI Tool** - Command-line interface for power users
- **REST API** - Programmatic access for automation

### 2. API Gateway (Azure Functions)
- Receives and validates infrastructure requests
- Performs schema validation and policy checks
- Estimates costs before submission
- Queues requests to Azure Service Bus

### 3. Request Queue (Azure Service Bus)
- Priority-based queuing (prod > staging > dev)
- Message persistence and retry handling
- Dead-letter queue for failed messages

### 4. Request Tracking (Azure Cosmos DB)
- Stores request metadata and status
- Tracks provisioning progress
- Maintains audit trail

### 5. GitHub Actions Workers
- Queue consumer workflow (runs every minute)
- Provision worker workflow (executes Terraform)
- Self-hosted runners on AKS

### 6. Self-Hosted Runners (AKS)
- Dedicated node pools per business unit
- Auto-scaling based on queue depth
- Pre-installed with Terraform, Azure CLI, kubectl

### 7. Terraform Modules
- Catalog-driven architecture
- Reusable modules for each resource type
- Hierarchical state management

## Request Flow

```
Developer -> CLI/Portal -> API Gateway -> Service Bus Queue
                                              |
                                              v
                          GitHub Actions <- Queue Consumer
                                              |
                                              v
                                     Provision Worker
                                              |
                                              v
                                    Terraform Apply
                                              |
                                              v
                                    Azure Resources
```

## Security Model

- **Authentication**: Azure Entra ID (OIDC)
- **Authorization**: RBAC per business unit
- **Secrets**: Azure Key Vault
- **Network**: Private endpoints (optional)

## Scalability

- Handles 1000s of requests per day
- Supports 100s of teams
- Auto-scales runners 1-20 per business unit
