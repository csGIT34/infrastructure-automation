# Platform Infrastructure

Bootstrap infrastructure for the simplified platform.

## State Storage (Bootstrap)

The state-storage configuration creates Azure Storage for storing Terraform state files.

### Resources Created

- **Resource Group**: For state storage
- **Storage Account**: GRS replication, versioning, soft delete
- **Container**: `tfstate` for state files
- **Security Groups**: State readers and admins
- **RBAC Assignments**: Least-privilege access

### Initial Deployment

This is the first thing you need to deploy. It uses LOCAL state initially.

```bash
cd terraform/platform/state-storage

# Create a tfvars file
cat > terraform.tfvars <<EOF
subscription_id = "00000000-0000-0000-0000-000000000000"
project         = "terraform-state"
environment     = "prod"
location        = "eastus"
business_unit   = "platform"
owners          = ["admin@company.com"]
replication_type = "GRS"
EOF

# Initialize with LOCAL state (no remote backend yet)
terraform init

# Review and apply
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

### Outputs

After creation, you'll get:

- **storage_account_name**: Use this for `TF_STATE_STORAGE_ACCOUNT` secret
- **container_name**: Use this for `TF_STATE_CONTAINER` secret (default: `tfstate`)
- **security_groups**: Groups for managing state access

### GitHub Secrets

Add these secrets to your GitHub repository:

```
TF_STATE_STORAGE_ACCOUNT=<storage_account_name from output>
TF_STATE_CONTAINER=tfstate
```

### State Paths

The workflow uses state paths in this format:
```
{pattern}-{size}.tfstate
```

Examples:
- `postgresql-small.tfstate`
- `keyvault-large.tfstate`
- `web-app-medium.tfstate`

### Migrate to Remote State (Optional)

After creation, you can optionally migrate this config to use its own remote state:

1. Uncomment the `backend "azurerm"` block in `main.tf`
2. Create `backend.tfvars`:
   ```hcl
   resource_group_name  = "<from output>"
   storage_account_name = "<from output>"
   container_name       = "tfstate"
   key                  = "platform/state-storage/terraform.tfstate"
   ```
3. Run: `terraform init -migrate-state -backend-config=backend.tfvars`

### Security Groups

| Group | Purpose | RBAC Role |
|-------|---------|-----------|
| `*-state-readers` | Read Terraform state | Storage Blob Data Reader |
| `*-state-admins` | Full access to state | Storage Blob Data Contributor |

Add users to these groups in Entra ID to grant access.

## Notes

- **State Locking**: Azure Storage provides built-in state locking via blob leases
- **Versioning**: Enabled on the storage account (30-day soft delete)
- **Replication**: GRS (geo-redundant) by default for disaster recovery
- **Access**: All access via RBAC (no storage account keys needed)
