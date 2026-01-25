# Dry Run API

Pre-commit validation API that validates and resolves pattern requests without provisioning.

## Overview

The Dry Run API allows developers to validate their `infrastructure.yaml` before committing, showing:
- Validation errors and warnings
- What components will be provisioned
- Estimated monthly costs
- Environment-specific features that will be enabled

## API Endpoint

```
POST /api/dry-run
```

### Request

Body: YAML content (infrastructure.yaml)

```yaml
version: "1"
metadata:
  project: myapp
  environment: dev
  business_unit: engineering
  owners:
    - alice@company.com
pattern: keyvault
pattern_version: "1.0.0"
config:
  name: secrets
  size: small
```

### Response

```json
{
  "valid": true,
  "document_count": 1,
  "documents": [{
    "index": 0,
    "pattern": "keyvault",
    "action": "create",
    "valid": true,
    "errors": [],
    "warnings": [],
    "components": ["keyvault", "security-groups", "rbac-assignments"],
    "estimated_cost_usd": 30,
    "resource_group": "rg-myapp-keyvault-dev",
    "environment_features": []
  }],
  "total_monthly_cost_usd": 30,
  "execution_order": [0],
  "create_count": 1,
  "destroy_count": 0
}
```

## Authentication

The API uses Entra ID (Azure AD) authentication with OAuth 2.0 bearer tokens.

### Portal Integration (Recommended)

The portal uses MSAL.js for browser-based authentication. See the `portal_msal_config`
Terraform output for the complete configuration:

```javascript
// Get configuration from: terraform output portal_msal_config
const msalConfig = {
  auth: {
    clientId: "<portal_client_id>",
    authority: "https://login.microsoftonline.com/<tenant_id>",
    redirectUri: window.location.origin
  }
};

const apiConfig = {
  endpoint: "https://<func>.azurewebsites.net/api/dry-run",
  scopes: ["api://infra-platform-dry-run-api/Patterns.Validate"]
};
```

### Local Development (No Auth)

When running locally with `func start`, authentication is not enforced:

```bash
curl -X POST "http://localhost:7071/api/dry-run" \
  -H "Content-Type: text/yaml" \
  -d @infrastructure.yaml
```

### Production Testing

For testing the deployed API, use the portal or a custom MSAL client.
Azure CLI cannot directly obtain tokens for custom APIs.

### Entra ID Configuration

| Setting | Value |
|---------|-------|
| API Client ID | See `terraform output entra_auth` |
| Portal Client ID | See `terraform output entra_auth` |
| Scope | `api://infra-platform-dry-run-api/Patterns.Validate` |
| Authority | `https://login.microsoftonline.com/<tenant_id>` |

## Local Development

### Prerequisites

- Python 3.11+
- Azure Functions Core Tools (`npm install -g azure-functions-core-tools@4`)

### Setup

```bash
cd terraform/platform/api/functions

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # Linux/Mac
# .venv\Scripts\activate  # Windows

# Install dependencies
pip install -r requirements.txt

# Copy pattern config for local development
mkdir -p config
cp -r ../../../../config/patterns config/
cp ../../../../config/sizing-defaults.yaml config/

# Start local function
func start
```

### Test locally

```bash
curl -X POST "http://localhost:7071/api/dry-run" \
  -H "Content-Type: text/yaml" \
  -d @examples/keyvault-pattern.yaml
```

## Deployment

### Infrastructure

Deploy the Function App infrastructure first:

```bash
cd terraform/platform/api
terraform init -backend-config="..."
terraform apply
```

### Function Code

Deploy the function code using the deploy script:

```bash
# Get the function app name
FUNC_NAME=$(terraform output -raw function_app | jq -r .name)

# Deploy
./functions/deploy.sh $FUNC_NAME
```

## Multi-Document Support

The API supports multi-document YAML (documents separated by `---`):

```yaml
---
version: "1"
action: destroy
metadata:
  project: myapp
  environment: dev
  business_unit: engineering
  owners: [alice@company.com]
pattern: postgresql
pattern_version: "1.0.0"
config:
  name: olddb
---
version: "1"
metadata:
  project: myapp
  environment: dev
  business_unit: engineering
  owners: [alice@company.com]
pattern: keyvault
pattern_version: "1.0.0"
config:
  name: secrets
```

Response includes execution order (destroy actions first):

```json
{
  "valid": true,
  "document_count": 2,
  "execution_order": [0, 1],
  "create_count": 1,
  "destroy_count": 1
}
```

## Error Handling

### Validation Errors

```json
{
  "valid": false,
  "documents": [{
    "index": 0,
    "valid": false,
    "errors": [
      "Missing required field: pattern",
      "Missing required metadata field: environment"
    ]
  }],
  "errors": [
    "Document 0: Missing required field: pattern",
    "Document 0: Missing required metadata field: environment"
  ]
}
```

### HTTP Status Codes

| Code | Description |
|------|-------------|
| 200 | All patterns valid |
| 400 | Validation errors or invalid YAML |
| 401 | Unauthorized - missing or invalid Entra ID token |
| 500 | Internal server error |
