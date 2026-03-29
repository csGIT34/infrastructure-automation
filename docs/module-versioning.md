# Module Versioning and Lifecycle

How to version, update, and add Terraform modules and patterns.

## Architecture

Every module and pattern lives in its own Git repo. The infrastructure-automation repo coordinates them.

```
infrastructure-automation/             (orchestration hub)
  config/patterns/*.yaml               (pattern definitions — source of truth)
  .github/workflows/
    prototype-provision.yaml            (checks out pattern repos at pinned tag)
  app-infrastructure/.github/workflows/
    terraform-apply.yaml                (checks out pattern repos at pinned tag)

terraform-azurerm-key-vault/           (module repo — independently versioned)
  main.tf, variables.tf, outputs.tf    (module implementation)
  pattern/                             (pattern wrapper using this module)
    main.tf                            (references modules via source= with pinned tags)
    variables.tf
    outputs.tf
  .github/workflows/release.yaml       (auto-creates GitHub release on tag push)

terraform-pattern-web-backend/         (composite pattern repo)
  main.tf                              (references multiple module repos via source=)
  variables.tf, outputs.tf
  .github/workflows/release.yaml
```

## Version Pinning Strategy

Versions are pinned at three levels:

| Level | Where | Example |
|-------|-------|---------|
| **Workflow → Pattern repo** | `ref:` in prototype-provision.yaml and terraform-apply.yaml | `ref: v1.1.3` |
| **Pattern → Module repos** | `source =` in pattern main.tf | `source = "github.com/AzSkyLab/terraform-azurerm-naming?ref=v1.0.1"` |
| **Module repos** | Git tags | `v1.0.1` |

All version references are explicit. No floating tags, no `latest`, no branch refs.

## Current Versions

| Repo | Tag | Notes |
|------|-----|-------|
| `terraform-pattern-web-backend` | v1.1.3 | 5-env validation |
| `terraform-azurerm-postgresql` | v1.1.3 | 5-env validation |
| `terraform-azurerm-key-vault` | v1.1.3 | 5-env validation |
| `terraform-azurerm-container-app` | v1.1.3 | 5-env validation |
| `terraform-azurerm-container-registry` | v1.1.3 | 5-env validation |
| `terraform-azurerm-naming` | v1.1.3 | 5-env abbreviations |
| `terraform-azurerm-resource-group` | v1.0.0 | |
| `terraform-azurerm-security-groups` | v1.0.0 | |
| `terraform-azurerm-rbac-assignments` | v1.0.0 | |

Workflow pinned ref: **v1.1.3**

## Updating an Existing Module

### Scenario: Fix a bug in `terraform-azurerm-postgresql`

#### Step 1: Make the change in the module repo

```bash
cd terraform-azurerm-postgresql
# Edit the module code
vim main.tf
# Also update the pattern wrapper if needed
vim pattern/variables.tf

git add .
git commit -m "fix: handle availability zone drift in flexible server"
```

#### Step 2: Tag and push

```bash
git tag v1.1.2
git push origin main --tags
```

This triggers `.github/workflows/release.yaml` in the module repo, which creates a GitHub release with auto-generated notes.

#### Step 3: Update pattern source refs (if this module is used by a composite pattern)

The `terraform-pattern-web-backend` includes PostgreSQL. Update its source reference:

```bash
cd terraform-pattern-web-backend
```

Edit `main.tf` — find the module source line:
```hcl
module "postgresql" {
  source = "github.com/AzSkyLab/terraform-azurerm-postgresql?ref=v1.1.1"
  #                                                         ^^^^^^^^
  # Change to v1.1.2
```

```bash
git add main.tf
git commit -m "fix: bump postgresql module to v1.1.2"
git tag v1.1.4
git push origin main --tags
```

#### Step 4: Bump the workflow pinned ref

Back in infrastructure-automation, update the pinned tag in both workflows:

**`.github/workflows/prototype-provision.yaml`:**
```yaml
- name: Checkout pattern repo
  uses: actions/checkout@v4
  with:
    repository: ${{ github.repository_owner }}/${{ steps.repo.outputs.repo }}
    ref: v1.1.4    # was v1.1.3
```

**`app-infrastructure/.github/workflows/terraform-apply.yaml`:**
```yaml
- name: Checkout pattern repo
  uses: actions/checkout@v4
  with:
    repository: ${{ github.repository_owner }}/${{ matrix.repo }}
    path: pattern-repo
    ref: v1.1.4    # was v1.1.3
```

```bash
cd infrastructure-automation
git add .github/workflows/prototype-provision.yaml \
        app-infrastructure/.github/workflows/terraform-apply.yaml
git commit -m "fix: bump pattern ref to v1.1.4 for postgresql zone drift fix"
git push origin main
```

#### Step 5: Update CLAUDE.md version table

Update the "Current Pattern Repo Versions" table in CLAUDE.md to reflect the new tags.

#### Step 6: Update the local reference copy (optional)

The `terraform/patterns/` and `terraform/modules/` directories in infrastructure-automation are reference copies. Update them to stay in sync:

```bash
# Copy the updated file
cp ../terraform-azurerm-postgresql/pattern/variables.tf \
   terraform/patterns/postgresql/variables.tf
git add terraform/patterns/postgresql/
git commit -m "sync: update postgresql reference copy"
```

### Summary: Update checklist

1. [ ] Change the module repo code
2. [ ] Commit and tag (semantic versioning)
3. [ ] Push tag (triggers auto-release)
4. [ ] Update composite pattern source refs if applicable
5. [ ] Tag the composite pattern repo
6. [ ] Bump `ref:` in both workflow files in infrastructure-automation
7. [ ] Update CLAUDE.md version table
8. [ ] Sync local reference copies

## Adding a New Module

### Scenario: Add `terraform-azurerm-redis`

#### Step 1: Create the module repo

Create a new GitHub repo `terraform-azurerm-redis` with this structure:

```
terraform-azurerm-redis/
  main.tf                    # Module implementation
  variables.tf               # Input variables
  outputs.tf                 # Output values
  pattern/                   # Pattern wrapper
    main.tf                  # References this module + naming, resource-group, etc.
    variables.tf             # Pattern-level variables (environment validation, sizing vars)
    outputs.tf               # Pattern outputs
  .github/workflows/
    release.yaml             # Auto-release on tag push
```

**`pattern/main.tf`** should reference shared modules with pinned tags:

```hcl
module "naming" {
  source = "github.com/AzSkyLab/terraform-azurerm-naming?ref=v1.0.1"

  project       = var.project
  environment   = var.environment
  name          = var.name
  resource_type = "redis"     # or appropriate type
  pattern_name  = "redis"
}

module "resource_group" {
  source = "github.com/AzSkyLab/terraform-azurerm-resource-group?ref=v1.0.0"

  name     = module.naming.resource_group_name
  location = var.location
  tags     = local.tags
}

module "security_groups" {
  source = "github.com/AzSkyLab/terraform-azurerm-security-groups?ref=v1.0.0"
  # ...
}

module "redis" {
  source = "../../"   # The module in the root of the same repo
  # ...
}
```

**`pattern/variables.tf`** must include:

```hcl
variable "environment" {
  type = string
  validation {
    condition     = contains(["prototype", "dev", "tst", "stg", "prd"], var.environment)
    error_message = "Environment must be 'prototype', 'dev', 'tst', 'stg', or 'prd'."
  }
}

# Standard variables: project, name, location, business_unit, owners,
# application_id, application_name, tier, cost_center
# All enterprise tag variables MUST have defaults

# Pattern-specific sizing variables with defaults
variable "sku_name" {
  type    = string
  default = "Basic"
}

variable "capacity" {
  type    = number
  default = 1
}
```

**`.github/workflows/release.yaml`:**

```yaml
name: Release
on:
  push:
    tags:
      - 'v*'
permissions:
  contents: write
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true
```

Tag and push:
```bash
git tag v1.0.0
git push origin main --tags
```

#### Step 2: Create the pattern YAML config

Create `config/patterns/redis.yaml` in infrastructure-automation:

```yaml
name: redis
description: |
  Azure Cache for Redis with security groups and RBAC.
category: single-resource
components:
  - resource-group
  - redis
  - security-groups
  - rbac-assignments
use_cases:
  - Session caching
  - Application caching
  - Message broker
sizing:
  small:
    prototype: { sku_name: "Basic", capacity: 0 }
    dev: { sku_name: "Basic", capacity: 0 }
    tst: { sku_name: "Basic", capacity: 0 }
    stg: { sku_name: "Standard", capacity: 1 }
    prd: { sku_name: "Standard", capacity: 1 }
  medium:
    prototype: { sku_name: "Standard", capacity: 1 }
    dev: { sku_name: "Standard", capacity: 1 }
    tst: { sku_name: "Standard", capacity: 1 }
    stg: { sku_name: "Standard", capacity: 2 }
    prd: { sku_name: "Premium", capacity: 1 }
  large:
    prototype: { sku_name: "Standard", capacity: 2 }
    dev: { sku_name: "Standard", capacity: 2 }
    tst: { sku_name: "Standard", capacity: 2 }
    stg: { sku_name: "Premium", capacity: 1 }
    prd: { sku_name: "Premium", capacity: 3 }
  xlarge:
    prototype: { sku_name: "Premium", capacity: 1 }
    dev: { sku_name: "Premium", capacity: 1 }
    tst: { sku_name: "Premium", capacity: 1 }
    stg: { sku_name: "Premium", capacity: 3 }
    prd: { sku_name: "Premium", capacity: 5 }
tier_defaults:
  1: { sku_name: "Premium" }
  2: { sku_name: "Premium" }
  3: { sku_name: "Standard" }
  4: { sku_name: "Basic" }
config:
  required:
    - name
  optional:
    - sku_name:
        type: string
        default: "Basic"
        description: Redis SKU (Basic, Standard, Premium)
```

The MCP server auto-discovers this file — no code changes needed.

#### Step 3: Add to GitHub App installation

Go to GitHub Settings > GitHub Apps > Infrastructure Automation > Repository access.

Add `terraform-azurerm-redis` to the list of accessible repositories.

#### Step 4: Add to workflow App token scoping

Both workflows need the repo listed in their `create-github-app-token` step so Terraform can clone private module sources.

**`.github/workflows/prototype-provision.yaml`** — add to the `repositories:` list:
```yaml
repositories: ${{ steps.repo.outputs.repo }},terraform-azurerm-naming,...,terraform-azurerm-redis
```

**`app-infrastructure/.github/workflows/terraform-apply.yaml`** — same:
```yaml
repositories: ${{ matrix.repo }},terraform-azurerm-naming,...,terraform-azurerm-redis
```

#### Step 5: Add to workflow_dispatch pattern options

**`.github/workflows/prototype-provision.yaml`:**
```yaml
pattern:
  type: choice
  options:
    - key_vault
    - postgresql
    - container_app
    - container_registry
    - web_backend
    - redis              # add this
```

#### Step 6: Create a local reference copy (optional)

```bash
mkdir -p terraform/patterns/redis
cp ../terraform-azurerm-redis/pattern/* terraform/patterns/redis/
```

#### Step 7: Update documentation

- Add to the "Available Patterns" table in CLAUDE.md and README.md
- Add to the "Current Pattern Repo Versions" table in CLAUDE.md

### Summary: New module checklist

1. [ ] Create module repo with main.tf, variables.tf, outputs.tf
2. [ ] Create pattern/ wrapper in the module repo
3. [ ] Add release.yaml workflow
4. [ ] Tag v1.0.0 and push
5. [ ] Create config/patterns/{name}.yaml (5 envs, 4 sizes)
6. [ ] Add repo to GitHub App installation
7. [ ] Add repo to `repositories:` in both workflow App token steps
8. [ ] Add pattern to `options:` in prototype-provision.yaml
9. [ ] Create local reference copy in terraform/patterns/
10. [ ] Update CLAUDE.md and README.md

## Adding a New Composite Pattern

Composite patterns combine multiple modules. They live in `terraform-pattern-{name}` repos (not `terraform-azurerm-{name}`).

The key differences from single-resource patterns:

1. **Repo naming:** `terraform-pattern-{name}` instead of `terraform-azurerm-{name}`
2. **TF directory:** `.` (root) instead of `pattern/`
3. **main.tf references multiple module repos** via `source = "github.com/AzSkyLab/terraform-azurerm-{module}?ref=v1.0.1"`
4. **Must be added to the COMPOSITES list** in both workflows:
   ```bash
   COMPOSITES="web_backend redis_app"  # space-separated
   ```

The rest of the process (pattern YAML, GitHub App, workflow options) is the same.

## Version Numbering Convention

Follow semantic versioning:

| Change Type | Version Bump | Example |
|-------------|-------------|---------|
| Bug fix, no variable changes | Patch (x.y.**Z**) | v1.0.0 → v1.0.1 |
| New optional variables, backward-compatible | Minor (x.**Y**.0) | v1.0.1 → v1.1.0 |
| Breaking changes (removed/renamed variables) | Major (**X**.0.0) | v1.1.0 → v2.0.0 |
| Environment validation expansion | Patch | v1.0.0 → v1.0.1 |

All repos in the ecosystem should be tagged consistently. The workflow's pinned `ref:` must match the highest-versioned pattern repo.

## Workflow Validation

### `terraform-test.yaml`

Runs on PR and push to main. Validates:
- Pattern YAML structure (required fields, valid categories)
- All sizing entries have all 5 environments
- MCP server imports correctly
- Resolver validates and resolves configs without error

### `validate-module-sync.yaml`

Runs weekly (Monday 6 AM UTC). Checks:
- Every pattern YAML in `config/patterns/` has a corresponding repo in the GitHub org
- Single-resource → `terraform-azurerm-{name}` exists
- Composite → `terraform-pattern-{name}` exists
- Reports missing repos as errors

## How the Workflow Resolves Pattern Repos

Both `prototype-provision.yaml` and `terraform-apply.yaml` use the same logic:

```bash
PATTERN_HYPHEN=$(echo "$PATTERN" | tr '_' '-')
COMPOSITES="web_backend"
if echo "$COMPOSITES" | grep -qw "$PATTERN"; then
  REPO="terraform-pattern-${PATTERN_HYPHEN}"
  TF_DIR="."
else
  REPO="terraform-azurerm-${PATTERN_HYPHEN}"
  TF_DIR="pattern"
fi
```

The repo is checked out at the pinned tag. `terraform init` then downloads any modules referenced in `source =` lines at their own pinned tags.

## Git Credentials for Private Modules

Both workflows configure git to use the GitHub App token for private module downloads:

```bash
git config --global url."https://x-access-token:${APP_TOKEN}@github.com/".insteadOf "https://github.com/"
```

This allows `terraform init` to clone private module repos referenced in `source = "github.com/..."` lines. The App token must have access to ALL repos that Terraform might reference.

## Common Issues

### Missing repo in App token scope

**Symptom:** `terraform init` fails with 404 cloning a module.

**Fix:** Add the repo to the `repositories:` list in the `create-github-app-token` step of both workflows.

### Forgotten ref bump

**Symptom:** New module changes aren't reflected in deployments.

**Fix:** Update `ref:` in both `prototype-provision.yaml` and `terraform-apply.yaml` to the new tag.

### Variable without default

**Symptom:** Terraform hangs waiting for interactive input in CI.

**Fix:** All enterprise tag variables (`application_id`, `application_name`, `tier`, `cost_center`) must have defaults in `variables.tf`. The MCP server may not always include them in tfvars.

### Pattern YAML missing an environment

**Symptom:** `terraform-test.yaml` fails validation.

**Fix:** Ensure every size in `sizing` has entries for all 5 environments: prototype, dev, tst, stg, prd.
