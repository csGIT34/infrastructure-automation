# Infrastructure Automation Platform (Simplified)

A simplified infrastructure platform for provisioning Azure resources using Terraform patterns with t-shirt sizing.

## Overview

This is a **simplified version** of the infrastructure platform, designed to match early-stage platform development. Teams work directly with Terraform tfvars files instead of YAML abstractions.

## Key Concepts

- **Patterns**: Pre-configured Terraform modules that provision complete infrastructure stacks
- **T-Shirt Sizing**: Three sizes (small, medium, large) with predefined configurations
- **Manual Workflow**: GitHub Actions workflow triggered manually to provision resources
- **Environment from Branch**: Environment determined by git branch (main=prod, staging=staging, other=dev)

## Quick Start

### 1. Trigger Provisioning

```bash
# Via GitHub UI
1. Go to Actions > Terraform Apply
2. Click "Run workflow"
3. Select pattern (e.g., postgresql)
4. Select size (small, medium, large)
5. Select action (plan, apply, destroy)
```

### 2. Local Terraform Execution

```bash
cd terraform/patterns/postgresql
terraform init
terraform plan -var-file=small.tfvars
terraform apply -var-file=small.tfvars
```

## Available Patterns

### Single-Resource Patterns
- **keyvault** - Key Vault with security groups and RBAC
- **postgresql** - PostgreSQL Flexible Server
- **storage** - Storage Account with containers
- **eventhub** - Event Hubs for streaming
- **function-app** - Azure Functions (serverless)
- **sql-database** - Azure SQL Database
- **mongodb** - Cosmos DB with MongoDB API
- **linux-vm** - Linux Virtual Machine
- **static-site** - Static Web App
- **aks-namespace** - Kubernetes namespace with quotas

### Composite Patterns
- **microservice** - AKS namespace + Event Hub + Storage
- **web-app** - Static Web App + Function App + Database
- **api-backend** - Function App + Database + Key Vault
- **data-pipeline** - Event Hub + Function + Storage + MongoDB

## T-Shirt Sizing

Each pattern has three pre-configured sizes:

| Size | Use Case | Characteristics |
|------|----------|----------------|
| **small** | Development | Minimal SKUs, single region, low cost |
| **medium** | Staging | Standard SKUs, single region, better performance |
| **large** | Production | Premium SKUs, HA enabled, multi-region, geo-redundant |

### Size Examples

**PostgreSQL:**
- Small: Burstable B1ms (1 vCore), 32GB, 7-day backup
- Medium: General Purpose D4s_v3 (4 vCores), 128GB, 14-day backup
- Large: Memory Optimized E8s_v3 (8 vCores), 512GB, geo-redundant backup

**Storage:**
- Small: LRS (locally redundant)
- Medium: ZRS (zone-redundant)
- Large: GZRS (geo-zone-redundant)

## Configuration

### Required Secrets

Add these to your GitHub repository secrets:

```
AZURE_TENANT_ID              # Azure tenant ID
AZURE_SUBSCRIPTION_ID        # Azure subscription ID
AZURE_CLIENT_ID_dev          # Service principal for dev
AZURE_CLIENT_ID_staging      # Service principal for staging
AZURE_CLIENT_ID_prod         # Service principal for prod
TF_STATE_STORAGE_ACCOUNT     # Storage account for state
TF_STATE_CONTAINER           # Container name (default: tfstate)
```

### Terraform State

State files are stored in Azure Storage with naming:
```
{pattern}-{size}.tfstate
```

Examples:
- `postgresql-small.tfstate`
- `keyvault-large.tfvars`

## Pattern Structure

Each pattern includes:
- **Security Groups** - Entra ID groups with owner delegation
- **RBAC Assignments** - Least-privilege access
- **Key Vault** - For secrets management
- **Diagnostics** - Log Analytics integration
- **Access Reviews** - Annual/quarterly reviews
- **Private Endpoints** - Network isolation

## Customizing Patterns

To customize a pattern:

1. Copy the tfvars file:
```bash
cp terraform/patterns/postgresql/small.tfvars terraform/patterns/postgresql/custom.tfvars
```

2. Edit the values:
```hcl
project       = "myproject"
name          = "mydb"
business_unit = "engineering"
owners        = ["alice@company.com"]
location      = "eastus"

# Customize sizing
sku                   = "GP_Standard_D2s_v3"
storage_mb            = 65536
backup_retention_days = 14
```

3. Run Terraform:
```bash
terraform plan -var-file=custom.tfvars
terraform apply -var-file=custom.tfvars
```

## Project Structure

```
.
├── .github/workflows/
│   ├── terraform-apply.yaml    # Manual provisioning workflow
│   └── terraform-test.yaml     # Pattern testing
├── scripts/
│   └── purge-keyvaults.sh      # Utility for cleaning up soft-deleted vaults
├── terraform/
│   ├── modules/                # Reusable Terraform modules
│   │   ├── naming/
│   │   ├── security-groups/
│   │   ├── rbac-assignments/
│   │   ├── keyvault/
│   │   ├── postgresql/
│   │   └── ...
│   └── patterns/               # Infrastructure patterns
│       ├── keyvault/
│       │   ├── main.tf
│       │   ├── small.tfvars
│       │   ├── medium.tfvars
│       │   └── large.tfvars
│       ├── postgresql/
│       └── ...
└── README.md
```

## Workflows

### terraform-apply.yaml

Manual workflow for provisioning:
- Dropdown selection for pattern and size
- Environment detected from branch
- OIDC authentication with Azure
- Terraform plan/apply/destroy

### terraform-test.yaml

Runs tests on patterns to validate:
- Terraform init/validate
- Variable validation
- Module integration

## Utilities

### Purge Soft-Deleted Key Vaults

```bash
./scripts/purge-keyvaults.sh
```

Lists and purges soft-deleted Key Vaults to free up names.

## Differences from Main Branch

This simplified version removes:
- YAML-based infrastructure requests
- Pattern resolution scripts
- Self-service portal
- MCP server
- GitOps workflows
- Pattern versioning system
- Multi-document YAML support

## Migration Path

To move back to the full platform (main branch):
1. Pattern tfvars files can be converted to YAML format
2. Modules and patterns remain compatible
3. Workflow integration can be added incrementally

## Contributing

When adding new patterns:
1. Create pattern directory in `terraform/patterns/`
2. Add `main.tf`, `variables.tf`, `outputs.tf`
3. Create `small.tfvars`, `medium.tfvars`, `large.tfvars`
4. Test with `terraform-test.yaml`

## Support

For issues or questions:
- Check existing patterns as examples
- Review Terraform module documentation
- Consult team documentation for Azure architecture standards
