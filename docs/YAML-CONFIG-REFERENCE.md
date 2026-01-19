# Infrastructure YAML Configuration Reference

This guide explains how to configure your `infrastructure.yaml` file to provision Azure resources through the self-service platform.

## Basic Structure

```yaml
metadata:
  project_name: my-project        # Required: unique project identifier
  environment: dev                # Required: dev, staging, or prod
  business_unit: engineering      # Required: your team/department
  cost_center: CC-1234           # Required: billing cost center
  owner_email: team@example.com  # Required: contact email
  location: centralus            # Optional: Azure region (default: centralus)

resources:
  - type: resource_type
    name: resource_name
    config:
      # Resource-specific configuration
```

## Available Resource Types

| Type | Description | Free Tier Available |
|------|-------------|---------------------|
| `function_app` | Azure Functions | Yes (`Y1` SKU) |
| `azure_sql` | Azure SQL Database | Yes (`Free` SKU) |
| `storage_account` | Azure Storage | No (but very low cost) |
| `keyvault` | Azure Key Vault | No |
| `postgresql` | Azure PostgreSQL Flexible Server | No |
| `mongodb` | Azure Cosmos DB (MongoDB API) | No |
| `eventhub` | Azure Event Hubs | No |
| `linux_vm` | Azure Virtual Machine | No |
| `static_web_app` | Azure Static Web Apps | Yes (`Free` SKU) |
| `aks_namespace` | AKS Namespace | No |

---

## Resource Configuration Details

### Azure Functions (`function_app`)

```yaml
- type: function_app
  name: api
  config:
    runtime: python              # python, node, dotnet, java, powershell
    runtime_version: "3.11"      # Version depends on runtime
    sku: Y1                      # SKU (see table below)
    os_type: Linux               # Linux or Windows
    cors_origins:                # Optional: CORS allowed origins
      - "https://myapp.com"
    app_settings:                # Optional: environment variables
      MY_SETTING: "value"
```

**SKU Options:**
| SKU | Description | Monthly Cost |
|-----|-------------|--------------|
| `Y1` | Consumption (pay per execution) | **Free** |
| `B1` | Basic | ~$13 |
| `S1` | Standard | ~$70 |
| `P1v2` | Premium | ~$140 |

**Recommendation:** Use `Y1` for dev environments.

---

### Azure SQL Database (`azure_sql`)

```yaml
- type: azure_sql
  name: database
  config:
    sku: Free                    # SKU (see table below)
    version: "12.0"              # SQL Server version
    admin_login: sqladmin        # Admin username
    databases:
      - name: appdb
        sku: Free                # Per-database SKU
        max_size_gb: 32          # Max database size
    firewall_rules:              # Optional: IP whitelist
      - name: AllowMyIP
        start_ip_address: "1.2.3.4"
        end_ip_address: "1.2.3.4"
```

**SKU Options:**
| SKU | Description | Monthly Cost |
|-----|-------------|--------------|
| `Free` | Free tier (32GB, limited vCores) | **Free** |
| `Basic` | Basic (2GB) | ~$5 |
| `S0` | Standard S0 | ~$15 |
| `S1` | Standard S1 | ~$30 |
| `P1` | Premium P1 | ~$465 |

**Recommendation:** Use `Free` for dev environments. Note: Free tier has limits (100k vCore seconds/month).

---

### Storage Account (`storage_account`)

```yaml
- type: storage_account
  name: data
  config:
    tier: Standard               # Standard or Premium
    replication: LRS             # LRS, GRS, ZRS, GZRS
    versioning: false            # Enable blob versioning
    soft_delete_days: 7          # Soft delete retention
    containers:
      - name: uploads
        access_type: private     # private, blob, container
```

---

### Key Vault (`keyvault`)

```yaml
- type: keyvault
  name: secrets
  config:
    sku: standard                # standard or premium
    enable_rbac: true            # Use RBAC instead of access policies
    soft_delete_days: 90         # Soft delete retention
```

---

### PostgreSQL (`postgresql`)

```yaml
- type: postgresql
  name: db
  config:
    sku: B_Standard_B1ms         # Server SKU
    version: "14"                # PostgreSQL version
    storage_mb: 32768            # Storage in MB
    database_name: mydb          # Initial database name
```

---

## Environment-Specific Examples

### Development (Free Tier)

```yaml
metadata:
  project_name: myapp
  environment: dev
  business_unit: engineering
  cost_center: CC-DEV
  owner_email: dev@example.com

resources:
  - type: function_app
    name: api
    config:
      runtime: python
      runtime_version: "3.11"
      sku: Y1                    # Free consumption plan

  - type: azure_sql
    name: db
    config:
      sku: Free                  # Free tier
      databases:
        - name: appdb
          sku: Free
```

**Estimated Cost: $0/month**

---

### Staging

```yaml
metadata:
  project_name: myapp
  environment: staging
  business_unit: engineering
  cost_center: CC-STAGING
  owner_email: team@example.com

resources:
  - type: function_app
    name: api
    config:
      runtime: python
      runtime_version: "3.11"
      sku: B1                    # Basic plan for consistent performance

  - type: azure_sql
    name: db
    config:
      sku: Basic
      databases:
        - name: appdb
          sku: S0
```

**Estimated Cost: ~$28/month**

---

### Production

```yaml
metadata:
  project_name: myapp
  environment: prod
  business_unit: engineering
  cost_center: CC-PROD
  owner_email: oncall@example.com

resources:
  - type: function_app
    name: api
    config:
      runtime: python
      runtime_version: "3.11"
      sku: P1v2                  # Premium for production

  - type: azure_sql
    name: db
    config:
      sku: S1
      databases:
        - name: appdb
          sku: S1
          max_size_gb: 250
```

**Estimated Cost: ~$170/month**

---

## Cost Limits by Environment

| Environment | Monthly Limit |
|-------------|---------------|
| dev | $500 |
| staging | $2,000 |
| prod | $10,000 |

Requests exceeding these limits will be rejected.

---

## Submitting Your Configuration

### Via CLI

```bash
infra provision infrastructure.yaml --email your@email.com
```

### Via API

```bash
curl -X POST https://api.infra.example.com/provision \
  -H "Content-Type: application/json" \
  -d '{
    "yaml_content": "$(cat infrastructure.yaml)",
    "requester_email": "your@email.com"
  }'
```

### Via GitOps

Add `infrastructure.yaml` to your repository and the platform will automatically provision on merge to main.

---

## Tips

1. **Start with free tiers** - For dev environments, always use `Y1` for Functions and `Free` for Azure SQL
2. **Use meaningful names** - Resource names should be descriptive (e.g., `api`, `worker`, `cache`)
3. **Tag your resources** - The platform automatically tags with project, environment, and owner
4. **Check the portal** - Track your request status at https://wonderful-field-088efae10.1.azurestaticapps.net
