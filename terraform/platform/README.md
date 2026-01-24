# Platform Infrastructure

This folder contains Terraform configurations for infrastructure that supports the Infrastructure Self-Service Platform itself.

## Components

| Folder | Description | Dependencies |
|--------|-------------|--------------|
| `state-storage/` | Terraform state storage (bootstrap) | None - apply first |
| `portal/` | Self-service portal (Azure Static Web App) | state-storage |

## Deployment Order

1. **state-storage** - Must be deployed first (uses local state initially)
2. **portal** - Depends on state-storage for remote state

---

## State Storage (Bootstrap)

The state-storage configuration creates the foundational infrastructure for storing Terraform state.

### Resources Created

- **Resource Group**: `rg-terraform-state-prod`
- **Storage Account**: With GRS replication, versioning, and soft delete
- **Container**: `tfstate` for state files
- **Security Groups**: For state readers and admins

### Initial Deployment

```bash
cd terraform/platform/state-storage

# Initialize with LOCAL state (no remote backend yet)
terraform init

# Review the plan
terraform plan -var-file=terraform.tfvars.json

# Create the state storage
terraform apply -var-file=terraform.tfvars.json
```

### Migrate to Remote State (Optional)

After creation, you can migrate this config to use its own remote state:

1. Uncomment the `backend "azurerm"` block in main.tf
2. Run:
   ```bash
   terraform init -migrate-state -backend-config=backend.tfvars
   ```

### State Paths

Use these paths for different components:

| Component | State Key |
|-----------|-----------|
| state-storage | `platform/state-storage/terraform.tfstate` |
| portal | `platform/portal/terraform.tfstate` |
| Pattern instances | `{business_unit}/{env}/{project}/{pattern}/terraform.tfstate` |

---

## Portal Infrastructure

The portal infrastructure provisions the Azure Static Web App that hosts the self-service portal.

### Prerequisites

- State storage must exist (deploy state-storage first)

### Resources Created

- **Resource Group**: `rg-infra-portal-prod`
- **Azure Static Web App**: Hosts the self-service portal
- **Security Groups**: For portal developers and admins
- **RBAC Assignments**: Reader/Contributor access

### Deployment

```bash
cd terraform/platform/portal

# Initialize with remote backend
terraform init -backend-config=backend.tfvars

# Review the plan
terraform plan -var-file=terraform.tfvars.json

# Apply
terraform apply -var-file=terraform.tfvars.json

# Get the deployment token for GitHub Actions
terraform output -raw static_web_app_api_key
```

### GitHub Actions Setup

After deploying, add the API key as a GitHub secret:

1. Get the key: `terraform output -raw static_web_app_api_key`
2. Go to repository Settings → Secrets → Actions
3. Add secret: `AZURE_STATIC_WEB_APPS_TOKEN`

### Configuration

Edit `terraform.tfvars.json` to customize:

```json
{
  "project": "infra-portal",
  "environment": "prod",
  "location": "eastus2",
  "business_unit": "platform",
  "owners": ["admin@company.com"],
  "sku_tier": "Standard",
  "sku_size": "Standard"
}
```

### SKU Options

| Tier | Features | Cost |
|------|----------|------|
| Free | 100GB bandwidth, 2 custom domains | $0 |
| Standard | 100GB bandwidth, 5 custom domains, password protection | $9/month |

---

## Security Groups

### State Storage Groups

| Group | Purpose |
|-------|---------|
| `sg-terraform-state-prod-state-readers` | Read Terraform state |
| `sg-terraform-state-prod-state-admins` | Full access to state storage |

### Portal Groups

| Group | Purpose |
|-------|---------|
| `sg-infra-portal-prod-portal-developers` | View portal resources |
| `sg-infra-portal-prod-portal-admins` | Manage portal and resources |

Add users to these groups in Entra ID to grant access.

---

## Quick Start

```bash
# 1. Deploy state storage (first time only)
cd terraform/platform/state-storage
terraform init
terraform apply -var-file=terraform.tfvars.json

# 2. Deploy portal
cd ../portal
terraform init -backend-config=backend.tfvars
terraform apply -var-file=terraform.tfvars.json

# 3. Get deployment token
terraform output -raw static_web_app_api_key

# 4. Add AZURE_STATIC_WEB_APPS_TOKEN secret to GitHub
# 5. Push code to trigger portal deployment
```
