# Infrastructure Platform Versioning Strategy

This document describes the versioning strategy for the infrastructure self-service platform, covering both platform developer and consumer experiences.

## Overview

The platform uses **per-pattern versioning** with semantic versioning (semver). Each pattern (keyvault, postgresql, etc.) has its own independent version lifecycle, allowing patterns to evolve at different rates while maintaining stability for consumers.

### Key Principles

1. **Per-pattern versions**: Each pattern has independent semantic versions
2. **Tag-triggered releases**: Git tags trigger release workflows
3. **Required version pinning**: Consumers must specify pattern versions
4. **Automated upgrade PRs**: Dependabot-style notifications for consumers
5. **Test-gated releases**: All tests must pass before release

---

## Git Tag Basics

If you're new to git tags, this section covers the fundamentals before diving into the platform's versioning system.

### What Are Git Tags?

Git tags are permanent markers that point to a specific commit. Unlike branches (which move forward as you add commits), tags stay fixed—they permanently mark a point in history.

```
commit A → commit B → commit C → commit D (main branch HEAD moves here)
                ↑
            tag: v1.0.0 (stays here forever)
```

Tags are ideal for marking releases because they provide a stable reference point that never changes.

### Tag Types

| Type | Description | Use Case |
|------|-------------|----------|
| **Lightweight** | Just a name pointing to a commit | Temporary or local markers |
| **Annotated** | Includes metadata (author, date, message) | Releases (what we use) |

### Common Git Tag Commands

```bash
# List all tags
git tag

# List tags matching a pattern
git tag -l "keyvault/*"

# View tag details (commit, date, message)
git show keyvault/v1.0.0

# See which commit a tag points to
git rev-list -n 1 keyvault/v1.0.0

# Create an annotated tag at current commit
git tag -a keyvault/v1.0.0 -m "Initial keyvault release"

# Create tag at a specific commit
git tag -a keyvault/v1.0.0 abc1234 -m "Release message"

# Push a single tag to remote
git push origin keyvault/v1.0.0

# Push all tags (use sparingly)
git push --tags

# Delete a local tag
git tag -d keyvault/v1.0.0

# Delete a remote tag
git push origin --delete keyvault/v1.0.0
```

### Tags vs Branches

| Aspect | Branches | Tags |
|--------|----------|------|
| **Purpose** | Active development | Mark releases |
| **Movement** | Moves with new commits | Fixed forever |
| **Naming** | `main`, `feature/xyz` | `keyvault/v1.0.0` |
| **Checkout** | For making changes | For viewing/building |

### How Tags Trigger Releases

When you push a tag to GitHub, it can trigger workflows. Our release workflow (`.github/workflows/release.yaml`) watches for tags matching `*/v*`:

```yaml
on:
  push:
    tags:
      - '*/v*'  # Matches: keyvault/v1.0.0, postgresql/v2.1.0, etc.
```

This is why creating a tag automatically creates a release—no manual GitHub Release creation needed.

---

## Version Scheme

### Tag Format

```
{pattern}/v{major}.{minor}.{patch}
```

**Examples:**
- `keyvault/v1.0.0` - Initial release of keyvault pattern
- `keyvault/v1.1.0` - New feature added to keyvault
- `keyvault/v1.1.1` - Bug fix to keyvault
- `postgresql/v2.0.0` - Breaking change in postgresql pattern

### Semantic Versioning Rules

| Change Type | Version Bump | Examples |
|-------------|--------------|----------|
| **MAJOR** | Breaking changes | Removed config option, changed output format, requires migration |
| **MINOR** | New features (backward compatible) | New config option, additional outputs, new component |
| **PATCH** | Bug fixes (backward compatible) | Security fix, documentation, default value change |

### Initial Versions

All existing patterns start at `v1.0.0` when versioning is enabled. This represents the current stable state.

---

## Platform Developer Experience

### Development Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│  1. Create Feature Branch                                        │
│     git checkout -b feature/keyvault-soft-delete                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. Make Changes                                                 │
│     - Edit terraform/patterns/keyvault/                          │
│     - Update terraform/modules/ if needed                        │
│     - Update config/patterns/keyvault.yaml                       │
│     - Add/update tests in terraform/tests/                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. Open Pull Request                                            │
│     - CI automatically detects changed patterns                  │
│     - Runs terraform tests for affected patterns only            │
│     - Shows test results in PR checks                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. Merge to Main (after review + tests pass)                    │
│     - Code is on main but NOT released                           │
│     - Can batch multiple changes before release                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. Create Release (when ready)                                  │
│     git tag keyvault/v1.2.0                                      │
│     git push origin keyvault/v1.2.0                              │
│     - Release workflow creates GitHub release                    │
│     - Changelog auto-generated from commits                      │
└─────────────────────────────────────────────────────────────────┘
```

### Local Testing (Unchanged)

Developers can still run tests locally:

```bash
# Test a specific module
cd terraform/tests/modules/keyvault
terraform init
terraform test -var-file=../../setup/terraform.tfvars

# Test a specific pattern
cd terraform/tests/patterns/keyvault
terraform init
terraform test -var-file=../../setup/terraform.tfvars

# Validate pattern config
python3 scripts/resolve-pattern.py examples/keyvault-pattern.yaml --validate
```

### CI Test Detection

The PR workflow automatically detects which patterns changed:

| Files Changed | Tests Run |
|---------------|-----------|
| `terraform/patterns/keyvault/**` | keyvault pattern tests |
| `terraform/modules/keyvault/**` | keyvault module + all patterns using it |
| `terraform/modules/security-groups/**` | All patterns (shared module) |
| `config/patterns/keyvault.yaml` | keyvault pattern tests |
| `scripts/resolve-pattern.py` | All pattern tests |

### Creating a Release

1. **Determine version bump**:
   - Check commits since last release for that pattern
   - Breaking change → MAJOR
   - New feature → MINOR
   - Bug fix → PATCH

2. **Create and push tag**:
   ```bash
   # Check current version
   git tag -l "keyvault/v*" | sort -V | tail -1
   # Output: keyvault/v1.1.0

   # Create new version
   git tag keyvault/v1.2.0
   git push origin keyvault/v1.2.0
   ```

3. **Release workflow runs automatically**:
   - Validates tests passed on main
   - Generates changelog from commits
   - Creates GitHub release
   - Updates VERSION file in pattern directory

### Release Notes Format

Auto-generated release notes include:

```markdown
## keyvault v1.2.0

### What's Changed

#### Features
- Add soft-delete configuration option (#123)
- Support custom purge protection days (#125)

#### Bug Fixes
- Fix RBAC assignment for readers group (#124)

#### Breaking Changes
None

### Upgrade Guide
No migration required. New `soft_delete` config option available.

### Full Changelog
https://github.com/org/infrastructure-automation/compare/keyvault/v1.1.0...keyvault/v1.2.0
```

---

## Consumer Developer Experience

### Version Pinning in infrastructure.yaml

Consumers must specify a version for each pattern:

```yaml
version: "1"
metadata:
  project: myapp
  environment: dev
  business_unit: engineering
  owners:
    - alice@company.com
  location: eastus

pattern: keyvault
pattern_version: "1.2.0"  # Required - pin to specific version
config:
  name: secrets
  size: small
```

### Multi-Pattern with Different Versions

```yaml
# Pattern 1: keyvault at v1.2.0
---
version: "1"
metadata:
  project: myapp
  environment: dev
  business_unit: engineering
  owners: [alice@company.com]

pattern: keyvault
pattern_version: "1.2.0"
config:
  name: secrets

# Pattern 2: postgresql at v2.1.0
---
version: "1"
metadata:
  project: myapp
  environment: dev
  business_unit: engineering
  owners: [alice@company.com]

pattern: postgresql
pattern_version: "2.1.0"
config:
  name: maindb
  size: medium
```

### Automated Update PRs

Consumer repos can add an update checker workflow that:

1. Runs weekly (configurable)
2. Checks for new versions of pinned patterns
3. Creates a PR with:
   - Updated versions in infrastructure.yaml
   - Changelog showing what's new
   - Breaking change warnings (if any)

**Example PR created by update checker:**

```markdown
## Update Infrastructure Patterns

This PR updates the following pattern versions:

| Pattern | Current | Latest | Change Type |
|---------|---------|--------|-------------|
| keyvault | 1.2.0 | 1.3.0 | Minor |
| postgresql | 2.1.0 | 2.1.1 | Patch |

### Changelog

#### keyvault 1.2.0 → 1.3.0
- Add network rules configuration option
- Support for user-assigned managed identity

#### postgresql 2.1.0 → 2.1.1
- Fix backup retention policy for staging environment

### Breaking Changes
None

---
Auto-generated by Infrastructure Update Checker
```

### Manual Version Check

Consumers can also check versions manually:

```bash
# List available versions for a pattern
gh release list --repo org/infrastructure-automation | grep "keyvault/"

# View release notes
gh release view keyvault/v1.3.0 --repo org/infrastructure-automation
```

### Upgrade Process

1. **Automated PR created** (or manual version bump)
2. **Review changelog** in PR description
3. **Check for breaking changes**:
   - If MAJOR version bump, review upgrade guide
   - May require config changes
4. **Merge PR** to update pinned version
5. **Provisioning runs** with new pattern version

---

## Directory Structure Changes

### Pattern VERSION Files

Each pattern directory gets a VERSION file:

```
terraform/patterns/
├── keyvault/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── VERSION          # Contains: 1.2.0
├── postgresql/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── VERSION          # Contains: 2.1.0
...
```

### CHANGELOG Files

Each pattern has a changelog:

```
terraform/patterns/
├── keyvault/
│   └── CHANGELOG.md
├── postgresql/
│   └── CHANGELOG.md
...
```

---

## Workflow Files

### New/Modified Workflows

| Workflow | Purpose | Trigger |
|----------|---------|---------|
| `terraform-test.yaml` | Run tests on PR (enhanced) | PR with terraform changes |
| `release.yaml` | Create releases | Tag push `*/v*` |
| `validate-module-sync.yaml` | Sync validation (unchanged) | PR/push |

### Consumer Workflows

| Template | Purpose | Location |
|----------|---------|----------|
| `infrastructure-workflow.yaml` | Validate & provision (updated) | Consumer repo |
| `update-checker-workflow.yaml` | Check for updates (new) | Consumer repo |

---

## Migration Plan

### Phase 1: Enable Versioning (No Breaking Changes)

1. Add VERSION files to all patterns (set to `1.0.0`)
2. Deploy new test workflow with smart detection
3. Deploy release workflow
4. Create initial `v1.0.0` releases for all patterns

### Phase 2: Update Consumer Workflow

1. Update infrastructure-workflow.yaml template to accept `pattern_version`
2. Make `pattern_version` optional initially (defaults to latest)
3. Update provision.yaml to handle versioned patterns
4. Notify consumers of new template version

### Phase 3: Require Version Pinning

1. Make `pattern_version` required in infrastructure.yaml
2. Provide update-checker-workflow.yaml template
3. Document upgrade process
4. Set deprecation date for non-versioned requests

---

## FAQ

### Q: What happens if I don't specify a version?

During the transition period, unversioned requests use the latest release. After Phase 3, a version is required and requests without it will fail validation.

### Q: Can I use unreleased features from main?

No. Only released versions can be used in production. This ensures stability and reproducibility. For testing new features, request a pre-release version from the platform team.

### Q: How do I know if an upgrade is safe?

Check the version bump type:
- **PATCH** (1.2.0 → 1.2.1): Safe, no changes required
- **MINOR** (1.2.0 → 1.3.0): Safe, new features available
- **MAJOR** (1.2.0 → 2.0.0): Review upgrade guide, may require config changes

### Q: Can I roll back to a previous version?

Yes. Update `pattern_version` in infrastructure.yaml to the previous version and the next provision will use that version. Note: Terraform state may require manual intervention for major version rollbacks.

### Q: How are module versions handled?

Modules are internal implementation details. When you pin a pattern version, you get the exact module versions that were tested with that pattern release. Modules don't have independent versions visible to consumers.
