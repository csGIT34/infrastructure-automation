# Branch-Per-Environment Strategy

> **Status:** Proposed
> **Author:** Platform Team
> **Date:** 2026-01-25

## Problem Statement

The current workflow requires developers to merge `infrastructure.yaml` to `main` before any resources are provisioned. This creates a chicken-and-egg problem:

- Developers want to test their app against real infrastructure before merging
- They can't get infrastructure without merging to main
- This forces merging "incomplete" work or relying on shared dev resources

Additionally, environment promotion requires editing the `environment` field in `infrastructure.yaml` for each promotion, which is error-prone and doesn't provide clear audit trails per environment.

## Proposed Solution

Adopt a **branch-per-environment** model where:

1. Developer repos have long-lived branches: `dev`, `qa`, `staging`, `prod`
2. Merging to each branch triggers provisioning for that environment
3. The environment is derived from the branch name, not from the yaml
4. Promotion happens by merging branch-to-branch

## Workflow

```
feature/add-database
        │
        ▼ (PR + merge)
       dev  ──────────► provisions to dev
        │
        ▼ (PR + merge)
       qa   ──────────► provisions to qa
        │
        ▼ (PR + merge)
     staging ─────────► provisions to staging
        │
        ▼ (PR + merge)
      prod  ──────────► provisions to prod
```

Developers promote infrastructure by merging up the branch chain. The `infrastructure.yaml` content stays identical across environments.

## Schema Changes

### Current Schema

```yaml
version: "1"
metadata:
  project: myapp
  environment: dev  # Must be edited for each promotion
  business_unit: engineering
  owners:
    - alice@company.com
  location: eastus

pattern: keyvault
pattern_version: "1.0.0"
config:
  name: secrets
```

### Proposed Schema

```yaml
version: "2"  # Bump version to indicate new schema
metadata:
  project: myapp
  # environment field removed - derived from branch
  business_unit: engineering
  owners:
    - alice@company.com
  location: eastus

pattern: keyvault
pattern_version: "1.0.0"
config:
  name: secrets
```

## Required Changes

### 1. Workflow Template (`templates/infrastructure-workflow.yaml`)

```yaml
name: Infrastructure GitOps

on:
  push:
    branches: [dev, qa, staging, prod]
    paths: ['infrastructure.yaml']
  pull_request:
    branches: [dev, qa, staging, prod]
    paths: ['infrastructure.yaml']

jobs:
  validate-and-plan:
    runs-on: ubuntu-latest
    steps:
      - name: Derive environment from branch
        id: env
        run: |
          if [ "${{ github.event_name }}" == "pull_request" ]; then
            BRANCH="${{ github.base_ref }}"
          else
            BRANCH="${GITHUB_REF#refs/heads/}"
          fi
          echo "environment=$BRANCH" >> $GITHUB_OUTPUT

      - name: Validate pattern request
        run: |
          python3 scripts/resolve-pattern.py infrastructure.yaml \
            --validate \
            --environment ${{ steps.env.outputs.environment }}

  provision:
    if: github.event_name == 'push'
    needs: validate-and-plan
    runs-on: ubuntu-latest
    steps:
      - name: Derive environment from branch
        id: env
        run: |
          BRANCH="${GITHUB_REF#refs/heads/}"
          echo "environment=$BRANCH" >> $GITHUB_OUTPUT

      - name: Trigger provisioning
        uses: peter-evans/repository-dispatch@v3
        with:
          token: ${{ steps.app-token.outputs.token }}
          repository: ${{ vars.INFRA_AUTOMATION_REPO }}
          event-type: provision
          client-payload: >-
            {
              "repository": "${{ github.repository }}",
              "commit_sha": "${{ github.sha }}",
              "environment": "${{ steps.env.outputs.environment }}",
              "yaml_base64": "${{ steps.encode.outputs.yaml_base64 }}"
            }
```

### 2. Provision Workflow (`.github/workflows/provision.yaml`)

Update to accept environment from dispatch payload:

```yaml
env:
  # Use environment from payload instead of parsing from yaml
  ENVIRONMENT: ${{ github.event.client_payload.environment }}

jobs:
  provision:
    name: "${{ github.event.client_payload.environment }}: ${{ matrix.pattern }}"
    # ... rest of job
```

### 3. Pattern Resolution (`scripts/resolve-pattern.py`)

Add `--environment` flag to override/inject environment:

```python
parser.add_argument('--environment',
    help='Override environment (for branch-based workflows)')

# In resolution logic:
if args.environment:
    request['metadata']['environment'] = args.environment
```

### 4. JSON Schema (`schemas/infrastructure.yaml.json`)

- Make `environment` field optional in v2 schema
- Add schema version detection

### 5. Portal (`web/index.html`)

- Add branch selection dropdown
- Remove environment field from form when using branch-based mode
- Update generated yaml to omit environment field

### 6. Documentation

- Update `CLAUDE.md` with new workflow
- Update `infrastructure-platform-guide.md`
- Add migration guide for existing consumers

## Branch Protection Recommendations

| Branch | Protection Level |
|--------|------------------|
| `dev` | Require PR (no approvals required) |
| `qa` | Require PR + 1 approval |
| `staging` | Require PR + 2 approvals |
| `prod` | Require PR + 2 approvals + CODEOWNERS review |

## Environment-to-Branch Mapping

Support for custom branch names if needed:

```yaml
# In consumer repo: .github/infra-config.yaml (optional)
branch_mapping:
  dev: develop
  qa: quality-assurance
  staging: stage
  prod: main
```

Default mapping if no config exists:
- `dev` → dev environment
- `qa` → qa environment
- `staging` → staging environment
- `prod` → prod environment

## Migration Path

### Phase 1: Backward Compatibility
- Support both v1 (environment in yaml) and v2 (environment from branch)
- Detect schema version and handle accordingly
- Environment in yaml takes precedence if present

### Phase 2: Consumer Migration
- Consumers create environment branches
- Update workflow template in their repos
- Remove environment field from infrastructure.yaml
- Set up branch protection rules

### Phase 3: Deprecation
- Warn on v1 schema usage
- Set deprecation date
- Eventually require v2 schema

## Trade-offs

### Pros
- Natural promotion flow (merge up the chain)
- No yaml editing between environments
- Clear audit trail per environment branch
- Environment-specific branch protection and approvals
- Developers can provision dev resources without touching main
- Easier to see what's deployed where (check each branch)

### Cons
- More branches to manage in consumer repos
- Potential merge conflicts if `infrastructure.yaml` diverges
- Developers need to understand the branch promotion model
- Initial setup overhead for existing consumers
- Need to handle branch naming variations

## Open Questions

1. **QA environment**: Do we need `qa` or is `dev` → `staging` → `prod` sufficient?
2. **Branch naming**: Should we enforce exact names or allow mapping?
3. **Rollback**: How do we handle rollbacks? Revert commits or separate mechanism?
4. **Drift detection**: Should we add scheduled runs to detect drift per environment?

## Implementation Checklist

- [ ] Update `scripts/resolve-pattern.py` with `--environment` flag
- [ ] Update provision workflow to use payload environment
- [ ] Create new workflow template for branch-based model
- [ ] Update JSON schema for v2 (optional environment)
- [ ] Update portal for branch selection
- [ ] Add schema version detection logic
- [ ] Write migration guide for consumers
- [ ] Update CLAUDE.md
- [ ] Update infrastructure-platform-guide.md
- [ ] Test with a pilot consumer repo
- [ ] Create consumer setup script/checklist
