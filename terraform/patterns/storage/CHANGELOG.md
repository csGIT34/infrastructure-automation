# Changelog

All notable changes to the storage pattern.


## [2.0.0] - 2026-01-25

### Other Changes
- chore(storage): release v2.0.0 (2d45333)



## [2.0.0] - 2026-01-25

No notable changes in this release.


## [1.0.0] - 2026-01-25

### Features
- feat: add per-pattern versioning strategy (bd98743)

### Bug Fixes
- fix: Handle Azure SQL Free tier limitations (e7e56e1)
- fix: Make azure_sql AAD administrator block dynamic (b1b180a)

### Other Changes
- Add infrastructure self-service portal with CI/CD (e20b604)
- Add local Terraform testing framework and fix module issues (677d824)
- Fix access_review module calls to match new two-stage interface (cc4c8dc)
- Implement two-stage annual access review (1fe42d7)
- Fix access review module format for Graph API (d318212)
- Add msgraph provider for access reviews to all patterns (5b24dae)
- Fix parallel execution, access reviews, and keyvault naming (64dbe71)
- Disable Key Vault soft delete and purge protection (51ffcf6)
- Add unique resource group naming per pattern (4700f8f)
- Add conditional feature support to all patterns (9b90960)
- Upgrade all patterns to azurerm >= 4.0 (cbf4208)
- Clean up Terraform lock files (8e0e23a)
- Upgrade all modules to azurerm >= 4.0 for Flex Consumption support (d8d3ebe)
- Add Flex Consumption (FC1) support for Azure Functions (32c838d)
- Fix consumption plan creation to be idempotent (a96762f)
- Use azapi for consumption Function Apps to avoid VM quota issues (a555555)
- Fix security groups, change api-backend default to Azure SQL (0b6e9c9)
- Fix runtime_version defaults per runtime type (c1c091b)
- Fix function-app module: use conditional locals for runtime versions (3740691)
- Fix function-app module runtime version handling with dynamic blocks (6d0f864)
- Fix function-app module runtime version handling (c4b2b5f)
- Fix access-review module to use Microsoft Graph provider (a8aeebc)
- Fix access-review and network-rules modules (f66f52d)
- Fix Terraform variable syntax across all patterns (3886e7d)
- Redesign platform to pattern-only architecture (c6d569a)
- Fix: add Terraform SP as group owner to enable member management (95ad7e5)
- Fix: add enable_secrets_group flag to avoid keyvault_id null check (6a385ad)
- Fix: pass enable flags from catalog to RBAC module (36b01c9)
- Fix: use keys() to check resource map presence in RBAC module (c2a32ce)
- Fix: use map with static keys for secrets_user_principal_ids (d288685)
- Fix: use nonsensitive() for secret keys in for_each (afed55c)
- Add conditional RBAC groups and pass all resource IDs to project-rbac (73cb044)
- Add project RBAC and Key Vault secrets management (958d666)
- Add aks_namespace and linux_vm Terraform modules (f8a7d7a)
- Add eventhub module and sync MCP server with Terraform capabilities (2fff4bb)
- Add Azure Functions and Azure SQL to Terraform catalog (9fd74af)
- Add Azure Static Web App resource type support (0b4c1bd)
- Fix remaining Terraform module syntax errors (63a2d0f)
- Fix Terraform module syntax errors (ec70623)
- Initial commit: Enterprise Self-Service Infrastructure Platform (63e58a5)


