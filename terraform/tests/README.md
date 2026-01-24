# Terraform Testing Infrastructure

This directory contains end-to-end tests for all Terraform modules using `terraform test`.

Tests use **Service Principal authentication**, matching the GitHub Actions workflow environment.

## Prerequisites

1. **Terraform 1.6+** (for native test support)
2. **Azure CLI** installed
3. **Azure Service Principal** with required permissions:
   - Contributor (create resources)
   - User Access Administrator (create RBAC assignments)
   - Microsoft Graph: Group.Create, Group.Read.All, User.Read.All

## Quick Start

```bash
cd terraform/tests

# 1. Interactive setup (creates .env file)
./run-tests.sh --setup

# 2. Source the environment
source setup/.env

# 3. Run tests
./run-tests.sh --quick          # Quick test (no Azure resources)
./run-tests.sh -m keyvault      # Single module test
./run-tests.sh -m               # All module tests
./run-tests.sh -p keyvault      # Pattern test
./run-tests.sh --all            # Everything
```

## Service Principal Setup

### Create Service Principal (if needed)

```bash
# Create SP with Contributor role on subscription
az ad sp create-for-rbac \
  --name "terraform-test-sp" \
  --role Contributor \
  --scopes /subscriptions/YOUR_SUBSCRIPTION_ID

# Note the output:
# {
#   "appId": "CLIENT_ID",
#   "password": "CLIENT_SECRET",
#   "tenant": "TENANT_ID"
# }

# Add User Access Administrator role (for RBAC tests)
az role assignment create \
  --assignee CLIENT_ID \
  --role "User Access Administrator" \
  --scope /subscriptions/YOUR_SUBSCRIPTION_ID
```

### Add Graph API Permissions

For security group tests, the SP needs Graph API permissions:

```bash
# Get the SP object ID
SP_OBJECT_ID=$(az ad sp show --id CLIENT_ID --query id -o tsv)

# Add Graph permissions (requires admin consent)
# Group.Create, Group.Read.All, User.Read.All
az ad app permission add \
  --id CLIENT_ID \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions \
    bf7b1a76-6e77-406b-b258-bf5c7720e98f=Role \
    5b567255-7703-4780-807c-7be8301ae99b=Role \
    df021288-bdef-4463-88db-98f22de89214=Role

# Grant admin consent (requires Global Admin or Privileged Role Admin)
az ad app permission admin-consent --id CLIENT_ID
```

### Configure Local Environment

Option 1: Interactive setup
```bash
./run-tests.sh --setup
source setup/.env
```

Option 2: Manual setup
```bash
cp setup/env.example setup/.env
# Edit setup/.env with your values
source setup/.env
```

### Verify Setup

```bash
./run-tests.sh --status
```

## Directory Structure

```
tests/
├── README.md                    # This file
├── Makefile                     # Make-based runner
├── run-tests.sh                 # Shell-based runner (recommended)
├── setup/
│   ├── env.example              # Environment template
│   ├── providers.tf             # Provider configuration
│   └── variables.tf             # Common variables
├── modules/                     # Module-level tests
│   ├── naming/                  # Pure logic (no Azure)
│   ├── keyvault/
│   ├── storage-account/
│   ├── security-groups/
│   ├── rbac-assignments/
│   ├── postgresql/
│   └── function-app/
└── patterns/                    # Pattern tests (integration)
    └── keyvault/
```

## Running Tests

### Test Commands

```bash
# Check environment
./run-tests.sh --status

# Quick test (naming module, no Azure resources)
./run-tests.sh --quick

# Single module test
./run-tests.sh -m keyvault
./run-tests.sh -m storage-account

# All module tests
./run-tests.sh -m

# Pattern tests
./run-tests.sh -p keyvault

# All tests
./run-tests.sh --all
```

### Test Output

Tests show pass/fail status:
```
Testing modules/keyvault...
keyvault.tftest.hcl... in progress
  run "setup"... pass
  run "create_keyvault"... pass
  run "create_keyvault_with_secrets"... pass
keyvault.tftest.hcl... pass

✓ keyvault passed
```

## Test Naming Convention

All test resources use identifiable names:
- Resource groups: `rg-tftest-{module}-{random}`
- Resources: `{prefix}-tftest-{random}`

The `tftest` prefix makes cleanup easy:
```bash
# Find orphaned test resources
az group list --query "[?starts_with(name, 'rg-tftest-')]" -o table
```

## Cleanup

Tests automatically destroy resources on completion. If tests fail mid-run:

```bash
# Find orphaned resources
az group list --query "[?starts_with(name, 'rg-tftest-')]" -o table

# Delete specific group
az group delete --name rg-tftest-keyvault-abc123 --yes

# Delete all test groups (use with caution)
az group list --query "[?starts_with(name, 'rg-tftest-')].name" -o tsv | \
  xargs -I {} az group delete --name {} --yes --no-wait

# Delete orphaned security groups
az ad group list --query "[?starts_with(displayName, 'sg-tftest-')].displayName" -o tsv | \
  xargs -I {} az ad group delete --group {}
```

## Adding New Tests

### Module Test

1. Create directory:
   ```bash
   mkdir -p modules/{module_name}/{setup,{module_name}_test}
   ```

2. Create `{module_name}.tftest.hcl`:
   ```hcl
   variables {
     test_subscription_id = ""
     test_tenant_id       = ""
     test_location        = "eastus"
     test_owner_email     = ""
   }

   provider "azurerm" {
     features {}
     subscription_id = var.test_subscription_id
   }

   run "setup" {
     command = apply
     module { source = "./setup" }
   }

   run "test_name" {
     command = apply
     module { source = "./{module_name}_test" }
     variables {
       resource_suffix = run.setup.suffix
       location        = var.test_location
     }
     assert {
       condition     = output.some_value != ""
       error_message = "Value should not be empty"
     }
   }
   ```

3. Create `setup/main.tf`:
   ```hcl
   resource "random_string" "suffix" {
     length  = 6
     special = false
     upper   = false
   }
   output "suffix" { value = random_string.suffix.result }
   ```

4. Create `{module_name}_test/main.tf` with test fixture

## CI/CD Integration

The GitHub Actions workflow (`.github/workflows/terraform-test.yaml`) runs these tests using the same authentication pattern (OIDC instead of client secret in CI).

Required secrets for CI:
- `AZURE_CLIENT_ID_dev` - Service principal for dev environment
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `TEST_OWNER_EMAIL`

## Troubleshooting

### Authentication Errors

```bash
# Verify SP can authenticate
az login --service-principal \
  -u $ARM_CLIENT_ID \
  -p $ARM_CLIENT_SECRET \
  --tenant $ARM_TENANT_ID

# Check current account
az account show
```

### Graph API Permission Errors

If security group tests fail with permission errors:
1. Verify Graph permissions are granted
2. Ensure admin consent was given
3. Wait a few minutes for permission propagation

### Resource Conflicts

If you see naming conflicts:
```bash
# Check for existing resources
az group list --query "[?starts_with(name, 'rg-tftest-')]"

# Clean up
./run-tests.sh --status  # Shows cleanup commands
```

### Soft-Deleted Key Vaults

Key Vaults have soft delete enabled. If tests fail due to name conflicts:
```bash
# List soft-deleted vaults
az keyvault list-deleted --query "[?starts_with(name, 'kv-tftest')]"

# Purge specific vault
az keyvault purge --name kv-tftest-abc123
```
