# Internal Developer Platform Control Plane Guide

A comprehensive guide for building a self-service internal developer platform using Terraform, GitHub Actions, AKS, ArgoCD, and Linkerd — applying control plane principles from enterprise multitenant architecture.

---

## Table of Contents

1. [Introduction](#introduction)
2. [Control Plane vs Data Plane Separation](#control-plane-vs-data-plane-separation)
3. [Architecture Overview](#architecture-overview)
4. [Tenant Registry Design](#tenant-registry-design)
5. [Repository Structure](#repository-structure)
6. [Core Responsibilities](#core-responsibilities)
7. [Lifecycle Management](#lifecycle-management)
8. [Long-Running Operations & Failure Handling](#long-running-operations--failure-handling)
9. [Shared Component Management](#shared-component-management)
10. [Reliability](#reliability)
11. [Security](#security)
12. [Telemetry & Consumption Tracking](#telemetry--consumption-tracking)
13. [Terraform Module Patterns](#terraform-module-patterns)
14. [GitHub Actions Workflows](#github-actions-workflows)
15. [ArgoCD Integration](#argocd-integration)
16. [Linkerd Service Mesh Policies](#linkerd-service-mesh-policies)
17. [Operational Runbooks](#operational-runbooks)
18. [Checklist & Maturity Model](#checklist--maturity-model)

---

## Introduction

### What is a Control Plane?

A control plane is the management layer that handles administrative operations for your platform. It is separate from the **data plane**, where actual workloads run.

| Layer | Purpose | Your Platform |
|-------|---------|---------------|
| **Control Plane** | Provisions, configures, manages | Terraform, GitHub Actions, ArgoCD controllers |
| **Data Plane** | Runs workloads | AKS clusters, application namespaces |

### Why Apply Control Plane Principles?

When building an internal developer platform, you face the same challenges as SaaS providers:

- **Multiple tenants** (internal teams/applications) sharing infrastructure
- **Self-service** requirements for developer autonomy
- **Isolation** between teams for security and stability
- **Lifecycle management** for onboarding and offboarding
- **Governance** for cost tracking and compliance

Applying control plane principles brings structure, reliability, and scalability to your platform.

### Your Platform Stack

This guide assumes the following technology stack:

| Component | Role |
|-----------|------|
| **Terraform** | Infrastructure provisioning (Azure resources, Kubernetes resources) |
| **GitHub Actions** | Workflow orchestration and automation |
| **AKS (Azure Kubernetes Service)** | Container orchestration platform |
| **ArgoCD** | GitOps-based application delivery |
| **Linkerd** | Service mesh for mTLS, observability, traffic management |

---

## Control Plane vs Data Plane Separation

### The Principle

Keep control plane components isolated from tenant workloads. This provides:

- **Independent scaling**: Control plane has consistent resource needs; data plane scales with workload demand
- **Blast radius reduction**: Control plane issues don't affect running workloads
- **Security boundaries**: Privileged control plane credentials are isolated
- **Maintenance flexibility**: Update control plane without impacting applications

### Recommended Separation Strategies

#### Option 1: Dedicated Control Plane Cluster

```
┌─────────────────────────────────┐     ┌─────────────────────────────────┐
│   aks-platform-cluster          │     │   aks-workloads-cluster         │
│   (Control Plane)               │     │   (Data Plane)                  │
├─────────────────────────────────┤     ├─────────────────────────────────┤
│ ┌─────────────┐ ┌─────────────┐ │     │ ┌───────────┐ ┌───────────┐    │
│ │ argocd-     │ │ platform-   │ │     │ │ team-a    │ │ team-b    │    │
│ │ system      │ │ tooling     │ │     │ │ namespace │ │ namespace │    │
│ └─────────────┘ └─────────────┘ │     │ └───────────┘ └───────────┘    │
│ ┌─────────────┐ ┌─────────────┐ │     │ ┌───────────┐ ┌───────────┐    │
│ │ linkerd-    │ │ monitoring  │ │     │ │ team-c    │ │ team-d    │    │
│ │ system      │ │             │ │     │ │ namespace │ │ namespace │    │
│ └─────────────┘ └─────────────┘ │     │ └───────────┘ └───────────┘    │
└─────────────────────────────────┘     └─────────────────────────────────┘
```

**Pros**: Maximum isolation, independent scaling, clearer security boundaries
**Cons**: Higher cost, more infrastructure to manage

#### Option 2: Namespace Separation (Single Cluster)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         aks-cluster                                      │
├─────────────────────────────────────────────────────────────────────────┤
│  Control Plane Namespaces          │  Data Plane Namespaces             │
│  (Restricted Access)               │  (Team Access)                     │
│ ┌─────────────┐ ┌─────────────┐   │ ┌───────────┐ ┌───────────┐       │
│ │ argocd-     │ │ platform-   │   │ │ team-a    │ │ team-b    │       │
│ │ system      │ │ system      │   │ │           │ │           │       │
│ └─────────────┘ └─────────────┘   │ └───────────┘ └───────────┘       │
│ ┌─────────────┐ ┌─────────────┐   │ ┌───────────┐ ┌───────────┐       │
│ │ linkerd-    │ │ monitoring  │   │ │ team-c    │ │ team-d    │       │
│ │ system      │ │             │   │ │           │ │           │       │
│ └─────────────┘ └─────────────┘   │ └───────────┘ └───────────┘       │
└─────────────────────────────────────────────────────────────────────────┘
```

**Pros**: Simpler, lower cost, easier to start
**Cons**: Shared failure domain, more complex RBAC

#### Option 3: Hybrid (Recommended for Most)

```
┌─────────────────────────────────┐     ┌─────────────────────────────────┐
│   aks-platform-cluster          │     │   aks-workloads-prod            │
│   (Control Plane + Non-Prod)    │     │   (Production Data Plane)       │
├─────────────────────────────────┤     ├─────────────────────────────────┤
│ ┌─────────────┐ ┌─────────────┐ │     │ ┌───────────┐ ┌───────────┐    │
│ │ argocd-     │ │ dev-        │ │     │ │ team-a    │ │ team-b    │    │
│ │ system      │ │ namespaces  │ │     │ │ prod      │ │ prod      │    │
│ └─────────────┘ └─────────────┘ │     │ └───────────┘ └───────────┘    │
└─────────────────────────────────┘     └─────────────────────────────────┘
```

**Pros**: Production isolation, cost-effective for non-prod
**Cons**: Moderate complexity

### Implementation: Node Pool Separation

Even within a single cluster, use dedicated node pools:

```hcl
# terraform/modules/aks-cluster/main.tf

resource "azurerm_kubernetes_cluster_node_pool" "system" {
  name                  = "system"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = "Standard_D4s_v3"
  node_count            = 3

  node_labels = {
    "node-type" = "system"
  }

  node_taints = [
    "CriticalAddonsOnly=true:NoSchedule"
  ]
}

resource "azurerm_kubernetes_cluster_node_pool" "workloads" {
  name                  = "workloads"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = "Standard_D8s_v3"
  min_count             = 3
  max_count             = 20
  enable_auto_scaling   = true

  node_labels = {
    "node-type" = "workloads"
  }
}
```

### Implementation: Namespace RBAC

```yaml
# platform/rbac/platform-system-rbac.yaml

# Only platform team can access control plane namespaces
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: platform-admin
  namespace: platform-system
subjects:
  - kind: Group
    name: platform-team
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io
---
# Developers cannot access control plane namespaces
apiVersion: rbac.authorization.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-from-workloads
  namespace: platform-system
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              namespace-type: system
```

---

## Architecture Overview

### High-Level Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              Developer Experience                             │
├──────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ Pull        │  │ Portal /    │  │ CLI         │  │ Slack       │         │
│  │ Request     │  │ Backstage   │  │ Tool        │  │ Bot         │         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
└─────────┼────────────────┼────────────────┼────────────────┼─────────────────┘
          │                │                │                │
          ▼                ▼                ▼                ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                              Control Plane                                    │
├──────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                         GitHub Repository                                │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │ │
│  │  │ tenant-     │  │ terraform/  │  │ kubernetes/ │  │ .github/    │    │ │
│  │  │ registry/   │  │ modules/    │  │ manifests/  │  │ workflows/  │    │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                      │                                        │
│                                      ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                        GitHub Actions                                    │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐    │ │
│  │  │ Validate    │  │ Terraform   │  │ Generate    │  │ Sync        │    │ │
│  │  │ Config      │──▶ Plan/Apply  │──▶ Manifests   │──▶ ArgoCD      │    │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘    │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                      │                                        │
└──────────────────────────────────────┼────────────────────────────────────────┘
                                       │
          ┌────────────────────────────┼────────────────────────────┐
          ▼                            ▼                            ▼
┌──────────────────┐      ┌──────────────────┐      ┌──────────────────┐
│   Azure          │      │   AKS Cluster    │      │   External       │
│   Resources      │      │                  │      │   Services       │
├──────────────────┤      ├──────────────────┤      ├──────────────────┤
│ • Resource Groups│      │ • Namespaces     │      │ • DNS            │
│ • PostgreSQL     │      │ • RBAC           │      │ • Certificates   │
│ • Key Vault      │      │ • Network Policy │      │ • Monitoring     │
│ • Storage        │      │ • ArgoCD Apps    │      │ • Alerting       │
│ • Service Bus    │      │ • Linkerd Policy │      │                  │
└──────────────────┘      └──────────────────┘      └──────────────────┘
```

### Request Flow: New Application Onboarding

```
┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐     ┌─────────┐
│Developer│     │ GitHub  │     │ GitHub  │     │Terraform│     │  Azure  │
│         │     │  Repo   │     │ Actions │     │         │     │         │
└────┬────┘     └────┬────┘     └────┬────┘     └────┬────┘     └────┬────┘
     │               │               │               │               │
     │ 1. Create PR  │               │               │               │
     │ (app config)  │               │               │               │
     │──────────────▶│               │               │               │
     │               │               │               │               │
     │               │ 2. Trigger    │               │               │
     │               │    workflow   │               │               │
     │               │──────────────▶│               │               │
     │               │               │               │               │
     │               │               │ 3. Validate   │               │
     │               │               │    config     │               │
     │               │               │───────┐       │               │
     │               │               │       │       │               │
     │               │               │◀──────┘       │               │
     │               │               │               │               │
     │               │               │ 4. Terraform  │               │
     │               │               │    plan       │               │
     │               │               │──────────────▶│               │
     │               │               │               │               │
     │ 5. Review     │               │               │               │
     │    plan       │               │               │               │
     │◀──────────────│◀──────────────│◀──────────────│               │
     │               │               │               │               │
     │ 6. Approve    │               │               │               │
     │    & merge    │               │               │               │
     │──────────────▶│               │               │               │
     │               │               │               │               │
     │               │ 7. Trigger    │               │               │
     │               │    apply      │               │               │
     │               │──────────────▶│               │               │
     │               │               │               │               │
     │               │               │ 8. Terraform  │               │
     │               │               │    apply      │               │
     │               │               │──────────────▶│               │
     │               │               │               │               │
     │               │               │               │ 9. Create     │
     │               │               │               │    resources  │
     │               │               │               │──────────────▶│
     │               │               │               │               │
     │               │               │               │◀──────────────│
     │               │               │               │               │
     │               │               │ 10. Generate  │               │
     │               │               │     K8s       │               │
     │               │               │     manifests │               │
     │               │               │───────┐       │               │
     │               │               │       │       │               │
     │               │               │◀──────┘       │               │
     │               │               │               │               │
     │               │ 11. Commit    │               │               │
     │               │     manifests │               │               │
     │               │◀──────────────│               │               │
     │               │               │               │               │
     │               │               │               │               │
     │               │ 12. ArgoCD    │               │               │
     │               │     syncs     │               │               │
     │               │───────────────────────────────────────────────▶
     │               │               │               │               │
     │ 13. Ready     │               │               │               │
     │     notification              │               │               │
     │◀──────────────│◀──────────────│               │               │
     │               │               │               │               │
```

---

## Tenant Registry Design

### Purpose

The tenant registry is the **source of truth** for all applications and teams on your platform. It answers:

- What applications exist?
- Who owns them?
- What resources do they need?
- What is their current state?

### Schema Design

#### Application Configuration

```yaml
# tenant-registry/applications/payments-api.yaml
apiVersion: platform.company.com/v1
kind: Application
metadata:
  name: payments-api
  labels:
    team: payments-team
    domain: financial
    tier: tier-1
    cost-center: CC-1234
spec:
  # Team ownership
  owner:
    team: payments-team
    contacts:
      - email: payments-lead@company.com
        role: tech-lead
      - email: payments-oncall@company.com
        role: oncall
    slack-channel: "#payments-team"

  # Deployment target
  deployment:
    cluster: aks-prod-01
    namespace: payments
    environment: production

  # Infrastructure requirements
  infrastructure:
    # Kubernetes namespace configuration
    namespace:
      cpu-request-limit: "8"
      cpu-limit: "16"
      memory-request-limit: "16Gi"
      memory-limit: "32Gi"
      pod-limit: 50

    # Azure resources to provision
    azure-resources:
      - type: postgresql
        name: payments-db
        config:
          sku: GP_Gen5_4
          storage-gb: 256
          backup-retention-days: 30
          geo-redundant-backup: true

      - type: keyvault
        name: payments-kv
        config:
          sku: standard
          soft-delete-retention-days: 90

      - type: servicebus-namespace
        name: payments-sb
        config:
          sku: Standard
          queues:
            - name: payment-events
              max-size-mb: 5120
            - name: payment-dlq
              max-size-mb: 1024

      - type: storage-account
        name: paymentsblobs
        config:
          tier: Standard
          replication: GRS
          containers:
            - name: invoices
            - name: receipts

  # ArgoCD application configuration
  argocd:
    repo: https://github.com/company/payments-api
    path: deploy/overlays/production
    target-revision: main
    sync-policy:
      automated:
        prune: true
        self-heal: true
      sync-options:
        - CreateNamespace=false

  # Network policies
  networking:
    ingress:
      enabled: true
      host: payments.company.com
      tls: true
    allowed-namespaces:
      - orders
      - notifications
    external-access:
      - stripe.com
      - api.bank.com

  # Service mesh configuration
  linkerd:
    enabled: true
    proxy-cpu-request: 100m
    proxy-memory-request: 128Mi

  # Monitoring and alerting
  observability:
    metrics:
      enabled: true
      scrape-interval: 30s
    logging:
      enabled: true
      retention-days: 30
    tracing:
      enabled: true
      sample-rate: 0.1
    alerts:
      - name: high-error-rate
        severity: critical
        threshold: "error_rate > 0.05"
      - name: high-latency
        severity: warning
        threshold: "p99_latency > 500ms"

status:
  phase: active
  provisioned-at: "2024-01-15T10:30:00Z"
  last-modified: "2024-06-20T14:22:00Z"
  terraform-state: applied
  argocd-sync: synced
  health: healthy
```

#### Team Configuration

```yaml
# tenant-registry/teams/payments-team.yaml
apiVersion: platform.company.com/v1
kind: Team
metadata:
  name: payments-team
  labels:
    department: engineering
    cost-center: CC-1234
spec:
  display-name: Payments Team
  description: Handles all payment processing systems

  # Team members and roles
  members:
    - email: alice@company.com
      role: tech-lead
      azure-ad-group: payments-admins
    - email: bob@company.com
      role: developer
      azure-ad-group: payments-developers
    - email: carol@company.com
      role: developer
      azure-ad-group: payments-developers

  # Azure AD groups for RBAC
  azure-ad-groups:
    admins: payments-admins
    developers: payments-developers
    readers: payments-readers

  # Resource quotas across all team applications
  quotas:
    max-namespaces: 5
    max-cpu: "32"
    max-memory: "64Gi"
    max-azure-postgresql: 3
    max-azure-keyvault: 5

  # Contact information
  contacts:
    slack-channel: "#payments-team"
    pagerduty-service: payments-oncall
    email: payments-team@company.com

status:
  applications:
    - payments-api
    - payments-webhook
    - payments-worker
  total-cpu-allocated: "12"
  total-memory-allocated: "24Gi"
```

#### Cluster Configuration

```yaml
# tenant-registry/clusters/aks-prod-01.yaml
apiVersion: platform.company.com/v1
kind: Cluster
metadata:
  name: aks-prod-01
  labels:
    environment: production
    region: eastus2
spec:
  # Azure configuration
  azure:
    subscription-id: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    resource-group: rg-aks-prod-01
    location: eastus2

  # Kubernetes version
  kubernetes-version: "1.28"

  # Node pools
  node-pools:
    - name: system
      vm-size: Standard_D4s_v3
      count: 3
      mode: System
      taints:
        - CriticalAddonsOnly=true:NoSchedule
    - name: workloads
      vm-size: Standard_D8s_v3
      min-count: 5
      max-count: 50
      mode: User
      auto-scaling: true

  # Capacity limits
  capacity:
    max-namespaces: 100
    max-pods-per-namespace: 100
    reserved-cpu: "12"      # For system components
    reserved-memory: "24Gi"

  # Installed components
  components:
    argocd:
      version: "2.9.3"
      namespace: argocd-system
    linkerd:
      version: "2.14.0"
      namespace: linkerd
    cert-manager:
      version: "1.13.0"
      namespace: cert-manager
    external-dns:
      version: "0.14.0"
      namespace: external-dns

status:
  phase: healthy
  current-namespaces: 45
  node-count: 18
  available-cpu: "120"
  available-memory: "480Gi"
  last-health-check: "2024-06-20T15:00:00Z"
```

### Registry Validation

Create a JSON Schema or use a validation tool to ensure registry entries are valid:

```yaml
# .github/workflows/validate-registry.yaml
name: Validate Tenant Registry

on:
  pull_request:
    paths:
      - 'tenant-registry/**'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install yq
        run: |
          sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
          sudo chmod +x /usr/local/bin/yq

      - name: Validate Application Configs
        run: |
          for file in tenant-registry/applications/*.yaml; do
            echo "Validating $file..."

            # Check required fields
            yq e '.metadata.name' "$file" > /dev/null || exit 1
            yq e '.spec.owner.team' "$file" > /dev/null || exit 1
            yq e '.spec.deployment.cluster' "$file" > /dev/null || exit 1
            yq e '.spec.deployment.namespace' "$file" > /dev/null || exit 1

            # Validate cluster reference exists
            cluster=$(yq e '.spec.deployment.cluster' "$file")
            if [[ ! -f "tenant-registry/clusters/${cluster}.yaml" ]]; then
              echo "ERROR: Cluster $cluster not found"
              exit 1
            fi

            # Validate team reference exists
            team=$(yq e '.spec.owner.team' "$file")
            if [[ ! -f "tenant-registry/teams/${team}.yaml" ]]; then
              echo "ERROR: Team $team not found"
              exit 1
            fi

            echo "✓ $file is valid"
          done

      - name: Check Team Quotas
        run: |
          ./scripts/check-team-quotas.sh

---

## Repository Structure

### Recommended Layout

```
platform-control-plane/
│
├── .github/
│   └── workflows/
│       ├── validate.yaml              # PR validation
│       ├── onboard-application.yaml   # New app provisioning
│       ├── update-application.yaml    # Config changes
│       ├── offboard-application.yaml  # App decommissioning
│       ├── terraform-plan.yaml        # Terraform planning
│       ├── terraform-apply.yaml       # Terraform execution
│       └── drift-detection.yaml       # Scheduled drift checks
│
├── tenant-registry/
│   ├── applications/                  # Application configurations
│   │   ├── payments-api.yaml
│   │   ├── orders-api.yaml
│   │   └── notifications-service.yaml
│   ├── teams/                         # Team configurations
│   │   ├── payments-team.yaml
│   │   ├── orders-team.yaml
│   │   └── platform-team.yaml
│   ├── clusters/                      # Cluster configurations
│   │   ├── aks-prod-01.yaml
│   │   ├── aks-prod-02.yaml
│   │   └── aks-nonprod-01.yaml
│   └── archived/                      # Offboarded apps (for audit)
│       └── legacy-app.yaml
│
├── terraform/
│   ├── modules/                       # Reusable Terraform modules
│   │   ├── namespace-bundle/          # K8s namespace + RBAC + policies
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── README.md
│   │   ├── azure-postgresql/
│   │   ├── azure-keyvault/
│   │   ├── azure-storage-account/
│   │   ├── azure-servicebus/
│   │   ├── argocd-application/
│   │   └── linkerd-authorization/
│   │
│   ├── applications/                  # Per-application Terraform
│   │   ├── payments-api/
│   │   │   ├── main.tf
│   │   │   ├── terraform.tfvars
│   │   │   └── backend.tf
│   │   └── orders-api/
│   │
│   ├── clusters/                      # Cluster-level infrastructure
│   │   ├── aks-prod-01/
│   │   └── aks-nonprod-01/
│   │
│   └── shared/                        # Shared infrastructure
│       ├── dns-zones/
│       ├── container-registry/
│       └── monitoring/
│
├── kubernetes/
│   ├── base/                          # Base Kustomize configurations
│   │   ├── namespace/
│   │   │   ├── namespace.yaml
│   │   │   ├── resource-quota.yaml
│   │   │   ├── limit-range.yaml
│   │   │   └── kustomization.yaml
│   │   ├── rbac/
│   │   ├── network-policy/
│   │   └── linkerd-policy/
│   │
│   ├── overlays/                      # Environment-specific overlays
│   │   ├── production/
│   │   └── nonprod/
│   │
│   └── applications/                  # Generated app manifests
│       ├── payments-api/
│       │   ├── namespace.yaml
│       │   ├── rbac.yaml
│       │   ├── network-policy.yaml
│       │   ├── linkerd-policy.yaml
│       │   └── argocd-application.yaml
│       └── orders-api/
│
├── argocd/
│   ├── projects/                      # ArgoCD Projects (per team)
│   │   ├── payments-team.yaml
│   │   └── orders-team.yaml
│   ├── applicationsets/               # ArgoCD ApplicationSets
│   │   └── tenant-apps.yaml
│   └── config/
│       └── argocd-cm.yaml
│
├── scripts/
│   ├── generate-manifests.sh          # Generate K8s manifests from registry
│   ├── validate-registry.sh           # Validate tenant registry
│   ├── check-team-quotas.sh           # Verify quota compliance
│   ├── onboard-application.sh         # Onboarding automation
│   ├── offboard-application.sh        # Offboarding automation
│   └── drift-report.sh                # Detect configuration drift
│
├── templates/
│   ├── application.yaml.tmpl          # Template for new apps
│   ├── team.yaml.tmpl                 # Template for new teams
│   └── terraform-app/                 # Template for app Terraform
│       ├── main.tf.tmpl
│       └── backend.tf.tmpl
│
├── docs/
│   ├── onboarding-guide.md
│   ├── architecture.md
│   ├── runbooks/
│   │   ├── incident-response.md
│   │   └── disaster-recovery.md
│   └── adr/                           # Architecture Decision Records
│       ├── 001-tenant-registry.md
│       └── 002-terraform-structure.md
│
├── policies/
│   ├── opa/                           # Open Policy Agent policies
│   │   ├── require-resource-limits.rego
│   │   └── require-labels.rego
│   └── azure-policy/
│       └── allowed-locations.json
│
└── README.md
```

### Key Design Decisions

#### 1. Tenant Registry as Source of Truth

The `tenant-registry/` directory contains declarative configurations that drive all automation. Benefits:

- **Auditable**: Git history shows who changed what and when
- **Reviewable**: Pull requests for all changes
- **Recoverable**: Easy to restore from Git
- **Discoverable**: Single place to find all platform resources

#### 2. Terraform Modules for Reusability

The `terraform/modules/` directory contains composable, reusable modules. Each module:

- Does one thing well
- Has clear inputs and outputs
- Includes documentation
- Is versioned (via Git tags or a module registry)

#### 3. Generated Kubernetes Manifests

The `kubernetes/applications/` directory contains generated manifests. They are:

- Generated from tenant registry during CI
- Committed to Git for ArgoCD to sync
- Never edited manually

#### 4. Separation of Concerns

| Directory | Purpose | Modified By |
|-----------|---------|-------------|
| `tenant-registry/` | What should exist | Developers (via PR) |
| `terraform/modules/` | How to provision | Platform team |
| `terraform/applications/` | Per-app Terraform state | GitHub Actions |
| `kubernetes/applications/` | K8s manifests | GitHub Actions (generated) |
| `argocd/` | ArgoCD configuration | Platform team |

---

## Core Responsibilities

### 1. Resource Management

**Definition**: Provisioning and managing tenant-specific and shared resources.

#### Implementation: Terraform Modules

```hcl
# terraform/modules/namespace-bundle/main.tf

# Kubernetes namespace
resource "kubernetes_namespace" "app" {
  metadata {
    name = var.namespace_name

    labels = {
      "app.kubernetes.io/name"       = var.app_name
      "app.kubernetes.io/managed-by" = "platform-control-plane"
      "platform.company.com/team"    = var.team
      "platform.company.com/tier"    = var.tier
      "linkerd.io/inject"            = var.linkerd_enabled ? "enabled" : "disabled"
    }

    annotations = {
      "platform.company.com/cost-center" = var.cost_center
      "platform.company.com/owner"       = var.owner_email
    }
  }
}

# Resource quota
resource "kubernetes_resource_quota" "app" {
  metadata {
    name      = "${var.app_name}-quota"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = var.cpu_request_limit
      "requests.memory" = var.memory_request_limit
      "limits.cpu"      = var.cpu_limit
      "limits.memory"   = var.memory_limit
      "pods"            = var.pod_limit
    }
  }
}

# Limit range for default container limits
resource "kubernetes_limit_range" "app" {
  metadata {
    name      = "${var.app_name}-limits"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "500m"
        memory = "512Mi"
      }
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
      max = {
        cpu    = var.max_container_cpu
        memory = var.max_container_memory
      }
    }
  }
}

# RBAC: Team admin access
resource "kubernetes_role_binding" "team_admin" {
  metadata {
    name      = "${var.team}-admin"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "admin"
  }

  subject {
    kind      = "Group"
    name      = var.team_admin_group
    api_group = "rbac.authorization.k8s.io"
  }
}

# RBAC: Team developer access
resource "kubernetes_role_binding" "team_developer" {
  metadata {
    name      = "${var.team}-developer"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "edit"
  }

  subject {
    kind      = "Group"
    name      = var.team_developer_group
    api_group = "rbac.authorization.k8s.io"
  }
}

# Default network policy: deny all ingress by default
resource "kubernetes_network_policy" "default_deny" {
  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

# Network policy: allow from specific namespaces
resource "kubernetes_network_policy" "allow_namespaces" {
  count = length(var.allowed_namespaces) > 0 ? 1 : 0

  metadata {
    name      = "allow-from-namespaces"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        dynamic "namespace_selector" {
          for_each = var.allowed_namespaces
          content {
            match_labels = {
              "kubernetes.io/metadata.name" = namespace_selector.value
            }
          }
        }
      }
    }
  }
}
```

```hcl
# terraform/modules/namespace-bundle/variables.tf

variable "app_name" {
  description = "Name of the application"
  type        = string
}

variable "namespace_name" {
  description = "Kubernetes namespace name"
  type        = string
}

variable "team" {
  description = "Owning team name"
  type        = string
}

variable "tier" {
  description = "Application tier (tier-1, tier-2, tier-3)"
  type        = string
  default     = "tier-3"
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
}

variable "owner_email" {
  description = "Owner email for contact"
  type        = string
}

variable "cpu_request_limit" {
  description = "Total CPU requests allowed in namespace"
  type        = string
  default     = "4"
}

variable "cpu_limit" {
  description = "Total CPU limits allowed in namespace"
  type        = string
  default     = "8"
}

variable "memory_request_limit" {
  description = "Total memory requests allowed in namespace"
  type        = string
  default     = "8Gi"
}

variable "memory_limit" {
  description = "Total memory limits allowed in namespace"
  type        = string
  default     = "16Gi"
}

variable "pod_limit" {
  description = "Maximum number of pods in namespace"
  type        = number
  default     = 50
}

variable "max_container_cpu" {
  description = "Maximum CPU per container"
  type        = string
  default     = "2"
}

variable "max_container_memory" {
  description = "Maximum memory per container"
  type        = string
  default     = "4Gi"
}

variable "team_admin_group" {
  description = "Azure AD group for team admins"
  type        = string
}

variable "team_developer_group" {
  description = "Azure AD group for team developers"
  type        = string
}

variable "linkerd_enabled" {
  description = "Enable Linkerd injection"
  type        = bool
  default     = true
}

variable "allowed_namespaces" {
  description = "Namespaces allowed to access this namespace"
  type        = list(string)
  default     = []
}
```

### 2. Tenant Configuration Management

**Definition**: Storing and managing each tenant's specific configuration.

#### Implementation: Config from Registry

```bash
#!/bin/bash
# scripts/generate-terraform-vars.sh

# Reads tenant registry and generates Terraform variables

APP_NAME=$1
REGISTRY_FILE="tenant-registry/applications/${APP_NAME}.yaml"
OUTPUT_FILE="terraform/applications/${APP_NAME}/terraform.tfvars"

# Extract values from registry
namespace=$(yq e '.spec.deployment.namespace' "$REGISTRY_FILE")
cluster=$(yq e '.spec.deployment.cluster' "$REGISTRY_FILE")
team=$(yq e '.spec.owner.team' "$REGISTRY_FILE")
cost_center=$(yq e '.metadata.labels.cost-center' "$REGISTRY_FILE")
owner_email=$(yq e '.spec.owner.contacts[0].email' "$REGISTRY_FILE")

# Resource limits
cpu_request=$(yq e '.spec.infrastructure.namespace.cpu-request-limit' "$REGISTRY_FILE")
cpu_limit=$(yq e '.spec.infrastructure.namespace.cpu-limit' "$REGISTRY_FILE")
memory_request=$(yq e '.spec.infrastructure.namespace.memory-request-limit' "$REGISTRY_FILE")
memory_limit=$(yq e '.spec.infrastructure.namespace.memory-limit' "$REGISTRY_FILE")

# Get team AD groups
team_file="tenant-registry/teams/${team}.yaml"
admin_group=$(yq e '.spec.azure-ad-groups.admins' "$team_file")
dev_group=$(yq e '.spec.azure-ad-groups.developers' "$team_file")

# Generate tfvars
cat > "$OUTPUT_FILE" << EOF
# Auto-generated from tenant registry - DO NOT EDIT MANUALLY
# Source: ${REGISTRY_FILE}
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

app_name          = "${APP_NAME}"
namespace_name    = "${namespace}"
cluster_name      = "${cluster}"
team              = "${team}"
cost_center       = "${cost_center}"
owner_email       = "${owner_email}"

cpu_request_limit    = "${cpu_request}"
cpu_limit            = "${cpu_limit}"
memory_request_limit = "${memory_request}"
memory_limit         = "${memory_limit}"

team_admin_group     = "${admin_group}"
team_developer_group = "${dev_group}"
EOF

echo "Generated: $OUTPUT_FILE"
```

### 3. Consumption Tracking

**Definition**: Measuring resource consumption for billing and governance.

#### Implementation: Azure Tags + Kubernetes Labels

```hcl
# terraform/modules/azure-postgresql/main.tf

resource "azurerm_postgresql_flexible_server" "main" {
  name                = var.server_name
  resource_group_name = var.resource_group_name
  location            = var.location

  sku_name   = var.sku_name
  storage_mb = var.storage_mb
  version    = var.postgresql_version

  # Tags for cost allocation
  tags = {
    application    = var.app_name
    team           = var.team
    cost-center    = var.cost_center
    environment    = var.environment
    managed-by     = "platform-control-plane"
    provisioned-at = timestamp()
  }
}
```

#### Cost Allocation Report Script

```bash
#!/bin/bash
# scripts/cost-report.sh

# Generate cost report per team using Azure Cost Management

START_DATE=$(date -d "first day of last month" +%Y-%m-%d)
END_DATE=$(date -d "last day of last month" +%Y-%m-%d)

# Query Azure Cost Management API
az costmanagement query \
  --type Usage \
  --scope "subscriptions/${SUBSCRIPTION_ID}" \
  --timeframe Custom \
  --time-period start-date="$START_DATE" end-date="$END_DATE" \
  --dataset-aggregation '{"totalCost":{"name":"Cost","function":"Sum"}}' \
  --dataset-grouping name="TagKey" type="Tag" \
  --dataset-filter "{\"Tags\":{\"Name\":\"team\",\"Operator\":\"In\",\"Values\":[$(yq e '.metadata.name' tenant-registry/teams/*.yaml | xargs | tr ' ' ',')]}}" \
  -o json > /tmp/cost-report.json

# Generate report
echo "# Monthly Cost Report: $START_DATE to $END_DATE"
echo ""
echo "| Team | Cost |"
echo "|------|------|"

jq -r '.properties.rows[] | "| \(.[0]) | $\(.[1] | tonumber | floor) |"' /tmp/cost-report.json
```

### 4. Telemetry

**Definition**: Tracking feature usage and system performance per tenant.

#### Implementation: Prometheus + Grafana

```yaml
# kubernetes/base/monitoring/prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: tenant-metrics
  namespace: monitoring
spec:
  groups:
    - name: tenant-resource-usage
      interval: 60s
      rules:
        # CPU usage per namespace
        - record: namespace:container_cpu_usage_seconds_total:sum_rate
          expr: |
            sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (namespace)

        # Memory usage per namespace
        - record: namespace:container_memory_working_set_bytes:sum
          expr: |
            sum(container_memory_working_set_bytes{container!=""}) by (namespace)

        # Pod count per namespace
        - record: namespace:kube_pod_info:count
          expr: |
            count(kube_pod_info) by (namespace)

        # Request rate per namespace (if using Linkerd)
        - record: namespace:request_total:sum_rate
          expr: |
            sum(rate(request_total[5m])) by (namespace)

        # Error rate per namespace
        - record: namespace:request_errors_total:sum_rate
          expr: |
            sum(rate(request_total{classification="failure"}[5m])) by (namespace)
```

```yaml
# Grafana dashboard for platform team
# kubernetes/base/monitoring/grafana-dashboard-tenant.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-tenants
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  tenants.json: |
    {
      "title": "Tenant Resource Usage",
      "panels": [
        {
          "title": "CPU Usage by Namespace",
          "type": "timeseries",
          "targets": [
            {
              "expr": "topk(10, namespace:container_cpu_usage_seconds_total:sum_rate)",
              "legendFormat": "{{namespace}}"
            }
          ]
        },
        {
          "title": "Memory Usage by Namespace",
          "type": "timeseries",
          "targets": [
            {
              "expr": "topk(10, namespace:container_memory_working_set_bytes:sum / 1024 / 1024 / 1024)",
              "legendFormat": "{{namespace}}"
            }
          ]
        },
        {
          "title": "Request Rate by Namespace",
          "type": "timeseries",
          "targets": [
            {
              "expr": "topk(10, namespace:request_total:sum_rate)",
              "legendFormat": "{{namespace}}"
            }
          ]
        }
      ]
    }

---

## Lifecycle Management

### Application Lifecycle States

```
┌──────────┐     ┌──────────────┐     ┌──────────┐     ┌───────────┐     ┌──────────┐
│ Requested│────▶│ Provisioning │────▶│  Active  │────▶│ Suspended │────▶│ Archived │
└──────────┘     └──────────────┘     └──────────┘     └───────────┘     └──────────┘
                        │                   │                │
                        │                   │                │
                        ▼                   ▼                ▼
                 ┌──────────┐        ┌──────────┐     ┌──────────┐
                 │  Failed  │        │ Updating │     │ Deleting │
                 └──────────┘        └──────────┘     └──────────┘
```

### Onboarding Workflow

#### Step 1: Developer Submits Request

```yaml
# Developer creates PR adding:
# tenant-registry/applications/new-service.yaml

apiVersion: platform.company.com/v1
kind: Application
metadata:
  name: new-service
  labels:
    team: my-team
    cost-center: CC-1234
spec:
  owner:
    team: my-team
    contacts:
      - email: developer@company.com
        role: tech-lead
  deployment:
    cluster: aks-prod-01
    namespace: new-service
    environment: production
  infrastructure:
    namespace:
      cpu-request-limit: "4"
      memory-request-limit: "8Gi"
    azure-resources:
      - type: keyvault
        name: new-service-kv
  argocd:
    repo: https://github.com/company/new-service
    path: deploy/production
status:
  phase: requested
```

#### Step 2: Validation Workflow

```yaml
# .github/workflows/validate-onboard.yaml
name: Validate Onboarding Request

on:
  pull_request:
    paths:
      - 'tenant-registry/applications/*.yaml'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Detect new applications
        id: detect
        run: |
          # Find new application files in this PR
          NEW_APPS=$(git diff --name-only --diff-filter=A origin/main... | grep '^tenant-registry/applications/' | xargs -I{} basename {} .yaml)
          echo "new_apps=$NEW_APPS" >> $GITHUB_OUTPUT

      - name: Validate schema
        run: |
          for app in ${{ steps.detect.outputs.new_apps }}; do
            echo "Validating $app..."
            ./scripts/validate-application.sh "$app"
          done

      - name: Check team quotas
        run: |
          for app in ${{ steps.detect.outputs.new_apps }}; do
            team=$(yq e '.spec.owner.team' "tenant-registry/applications/${app}.yaml")
            ./scripts/check-team-quota.sh "$team" "$app"
          done

      - name: Check cluster capacity
        run: |
          for app in ${{ steps.detect.outputs.new_apps }}; do
            cluster=$(yq e '.spec.deployment.cluster' "tenant-registry/applications/${app}.yaml")
            ./scripts/check-cluster-capacity.sh "$cluster"
          done

      - name: Validate namespace uniqueness
        run: |
          for app in ${{ steps.detect.outputs.new_apps }}; do
            namespace=$(yq e '.spec.deployment.namespace' "tenant-registry/applications/${app}.yaml")
            cluster=$(yq e '.spec.deployment.cluster' "tenant-registry/applications/${app}.yaml")

            # Check if namespace already exists in registry
            existing=$(grep -r "namespace: ${namespace}" tenant-registry/applications/*.yaml | grep -v "${app}.yaml" || true)
            if [[ -n "$existing" ]]; then
              echo "ERROR: Namespace $namespace already exists"
              exit 1
            fi
          done

      - name: Generate Terraform plan
        run: |
          for app in ${{ steps.detect.outputs.new_apps }}; do
            ./scripts/generate-terraform-vars.sh "$app"
            cd "terraform/applications/${app}"
            terraform init
            terraform plan -out=tfplan
            cd -
          done

      - name: Post plan to PR
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const plan = fs.readFileSync('terraform/applications/${{ steps.detect.outputs.new_apps }}/tfplan.txt', 'utf8');
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `## Terraform Plan\n\`\`\`\n${plan}\n\`\`\``
            });
```

#### Step 3: Provisioning Workflow (On Merge)

```yaml
# .github/workflows/onboard-application.yaml
name: Onboard Application

on:
  push:
    branches: [main]
    paths:
      - 'tenant-registry/applications/*.yaml'

concurrency:
  group: onboard-${{ github.sha }}
  cancel-in-progress: false

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    outputs:
      new_apps: ${{ steps.detect.outputs.new_apps }}
      updated_apps: ${{ steps.detect.outputs.updated_apps }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2

      - name: Detect changes
        id: detect
        run: |
          NEW_APPS=$(git diff --name-only --diff-filter=A HEAD~1 HEAD | grep '^tenant-registry/applications/' | xargs -I{} basename {} .yaml || echo "")
          UPDATED_APPS=$(git diff --name-only --diff-filter=M HEAD~1 HEAD | grep '^tenant-registry/applications/' | xargs -I{} basename {} .yaml || echo "")
          echo "new_apps=$NEW_APPS" >> $GITHUB_OUTPUT
          echo "updated_apps=$UPDATED_APPS" >> $GITHUB_OUTPUT

  provision-new-apps:
    needs: detect-changes
    if: needs.detect-changes.outputs.new_apps != ''
    runs-on: ubuntu-latest
    strategy:
      matrix:
        app: ${{ fromJson(format('["{0}"]', join(split(needs.detect-changes.outputs.new_apps, ' '), '","'))) }}
      fail-fast: false
    steps:
      - uses: actions/checkout@v4

      - name: Update status to provisioning
        run: |
          yq e '.status.phase = "provisioning"' -i "tenant-registry/applications/${{ matrix.app }}.yaml"
          yq e '.status.provisioning-started = now' -i "tenant-registry/applications/${{ matrix.app }}.yaml"

      - name: Azure Login
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Generate Terraform configuration
        run: |
          ./scripts/generate-terraform-vars.sh "${{ matrix.app }}"
          ./scripts/generate-terraform-main.sh "${{ matrix.app }}"

      - name: Terraform Init
        working-directory: terraform/applications/${{ matrix.app }}
        run: terraform init

      - name: Terraform Apply
        id: terraform
        working-directory: terraform/applications/${{ matrix.app }}
        run: |
          terraform apply -auto-approve
          echo "outputs=$(terraform output -json)" >> $GITHUB_OUTPUT

      - name: Generate Kubernetes manifests
        run: |
          ./scripts/generate-k8s-manifests.sh "${{ matrix.app }}"

      - name: Generate ArgoCD Application
        run: |
          ./scripts/generate-argocd-app.sh "${{ matrix.app }}"

      - name: Update status to active
        run: |
          yq e '.status.phase = "active"' -i "tenant-registry/applications/${{ matrix.app }}.yaml"
          yq e '.status.provisioned-at = now' -i "tenant-registry/applications/${{ matrix.app }}.yaml"
          yq e '.status.terraform-state = "applied"' -i "tenant-registry/applications/${{ matrix.app }}.yaml"

      - name: Commit generated files
        run: |
          git config user.name "Platform Bot"
          git config user.email "platform-bot@company.com"
          git add .
          git commit -m "Provision: ${{ matrix.app }} - generated manifests and updated status"
          git push

      - name: Notify team
        uses: slackapi/slack-github-action@v1
        with:
          channel-id: ${{ env.TEAM_SLACK_CHANNEL }}
          payload: |
            {
              "text": "Application ${{ matrix.app }} has been provisioned successfully!",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Application Provisioned*\n• Name: `${{ matrix.app }}`\n• Namespace: `${{ env.NAMESPACE }}`\n• Cluster: `${{ env.CLUSTER }}`"
                  }
                }
              ]
            }

      - name: Handle failure
        if: failure()
        run: |
          yq e '.status.phase = "failed"' -i "tenant-registry/applications/${{ matrix.app }}.yaml"
          yq e '.status.error = "${{ steps.terraform.outcome }}"' -i "tenant-registry/applications/${{ matrix.app }}.yaml"
          git add .
          git commit -m "Provision FAILED: ${{ matrix.app }}"
          git push
```

### Offboarding Workflow

```yaml
# .github/workflows/offboard-application.yaml
name: Offboard Application

on:
  workflow_dispatch:
    inputs:
      application:
        description: 'Application name to offboard'
        required: true
        type: string
      confirmation:
        description: 'Type the application name again to confirm'
        required: true
        type: string
      preserve_data:
        description: 'Preserve data backups before deletion'
        required: true
        type: boolean
        default: true

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - name: Confirm application name
        if: inputs.application != inputs.confirmation
        run: |
          echo "ERROR: Application name confirmation does not match"
          exit 1

      - uses: actions/checkout@v4

      - name: Verify application exists
        run: |
          if [[ ! -f "tenant-registry/applications/${{ inputs.application }}.yaml" ]]; then
            echo "ERROR: Application ${{ inputs.application }} not found"
            exit 1
          fi

  backup:
    needs: validate
    if: inputs.preserve_data
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Backup databases
        run: |
          ./scripts/backup-application-data.sh "${{ inputs.application }}"

      - name: Backup Kubernetes resources
        run: |
          namespace=$(yq e '.spec.deployment.namespace' "tenant-registry/applications/${{ inputs.application }}.yaml")
          cluster=$(yq e '.spec.deployment.cluster' "tenant-registry/applications/${{ inputs.application }}.yaml")

          az aks get-credentials --resource-group "rg-${cluster}" --name "$cluster"
          kubectl get all -n "$namespace" -o yaml > "backups/${namespace}-resources.yaml"

      - name: Upload backups
        run: |
          az storage blob upload-batch \
            --account-name "${{ secrets.BACKUP_STORAGE_ACCOUNT }}" \
            --destination "offboarding/${{ inputs.application }}-$(date +%Y%m%d)" \
            --source backups/

  offboard:
    needs: [validate, backup]
    if: always() && needs.validate.result == 'success' && (needs.backup.result == 'success' || needs.backup.result == 'skipped')
    runs-on: ubuntu-latest
    environment: production  # Requires manual approval
    steps:
      - uses: actions/checkout@v4

      - name: Update status to deleting
        run: |
          yq e '.status.phase = "deleting"' -i "tenant-registry/applications/${{ inputs.application }}.yaml"
          yq e '.status.deletion-started = now' -i "tenant-registry/applications/${{ inputs.application }}.yaml"
          git add .
          git commit -m "Offboard: ${{ inputs.application }} - starting deletion"
          git push

      - name: Azure Login
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Remove ArgoCD Application
        run: |
          cluster=$(yq e '.spec.deployment.cluster' "tenant-registry/applications/${{ inputs.application }}.yaml")
          az aks get-credentials --resource-group "rg-${cluster}" --name "$cluster"

          # Delete ArgoCD application (this will delete K8s resources)
          kubectl delete application "${{ inputs.application }}" -n argocd-system --ignore-not-found

      - name: Wait for ArgoCD cleanup
        run: |
          namespace=$(yq e '.spec.deployment.namespace' "tenant-registry/applications/${{ inputs.application }}.yaml")

          # Wait for namespace to be cleaned up by ArgoCD
          for i in {1..30}; do
            if ! kubectl get namespace "$namespace" &> /dev/null; then
              echo "Namespace deleted"
              break
            fi
            echo "Waiting for namespace deletion... ($i/30)"
            sleep 10
          done

      - name: Terraform Destroy
        working-directory: terraform/applications/${{ inputs.application }}
        run: |
          terraform init
          terraform destroy -auto-approve

      - name: Archive application config
        run: |
          mv "tenant-registry/applications/${{ inputs.application }}.yaml" \
             "tenant-registry/archived/${{ inputs.application }}-$(date +%Y%m%d).yaml"

          # Update archived status
          yq e '.status.phase = "archived"' -i "tenant-registry/archived/${{ inputs.application }}-$(date +%Y%m%d).yaml"
          yq e '.status.archived-at = now' -i "tenant-registry/archived/${{ inputs.application }}-$(date +%Y%m%d).yaml"

      - name: Remove generated files
        run: |
          rm -rf "terraform/applications/${{ inputs.application }}"
          rm -rf "kubernetes/applications/${{ inputs.application }}"
          rm -f "argocd/applications/${{ inputs.application }}.yaml"

      - name: Commit changes
        run: |
          git add .
          git commit -m "Offboard: ${{ inputs.application }} - completed"
          git push

      - name: Notify team
        uses: slackapi/slack-github-action@v1
        with:
          channel-id: ${{ env.TEAM_SLACK_CHANNEL }}
          payload: |
            {
              "text": "Application ${{ inputs.application }} has been offboarded.",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Application Offboarded*\n• Name: `${{ inputs.application }}`\n• Backup preserved: `${{ inputs.preserve_data }}`\n• Archived config: `tenant-registry/archived/${{ inputs.application }}-$(date +%Y%m%d).yaml`"
                  }
                }
              ]
            }

---

## Long-Running Operations & Failure Handling

### The Challenge

Control plane operations often involve multiple steps that can fail at any point:

```
Onboard Application
├── 1. Validate configuration      ✓
├── 2. Create resource group       ✓
├── 3. Provision database          ✓
├── 4. Create Key Vault            ✓
├── 5. Store secrets               ✗ FAILED (timeout)
├── 6. Create namespace            (not started)
├── 7. Configure RBAC              (not started)
├── 8. Deploy ArgoCD app           (not started)
└── 9. Send notification           (not started)
```

### Principles for Handling Long-Running Operations

#### 1. Idempotency

Every operation must be safe to retry:

```hcl
# BAD: Creates duplicate on retry
resource "azurerm_resource_group" "app" {
  name     = "rg-${uuid()}"  # New name each time!
  location = var.location
}

# GOOD: Same result on retry
resource "azurerm_resource_group" "app" {
  name     = "rg-${var.app_name}"  # Deterministic name
  location = var.location
}
```

#### 2. State Tracking

Track the state of each step:

```yaml
# tenant-registry/applications/my-app.yaml
status:
  phase: provisioning
  steps:
    - name: validate-config
      status: completed
      completed-at: "2024-06-20T10:00:00Z"
    - name: create-resource-group
      status: completed
      completed-at: "2024-06-20T10:01:00Z"
    - name: provision-database
      status: completed
      completed-at: "2024-06-20T10:05:00Z"
    - name: create-keyvault
      status: completed
      completed-at: "2024-06-20T10:06:00Z"
    - name: store-secrets
      status: failed
      error: "Timeout after 300s"
      failed-at: "2024-06-20T10:11:00Z"
      retry-count: 2
    - name: create-namespace
      status: pending
    - name: configure-rbac
      status: pending
    - name: deploy-argocd-app
      status: pending
    - name: send-notification
      status: pending
```

#### 3. Retry Logic with Backoff

```yaml
# .github/workflows/provision-with-retry.yaml
jobs:
  provision:
    runs-on: ubuntu-latest
    steps:
      - name: Store secrets with retry
        uses: nick-fields/retry@v2
        with:
          timeout_minutes: 10
          max_attempts: 3
          retry_wait_seconds: 30
          command: |
            ./scripts/store-secrets.sh "${{ env.APP_NAME }}"

      - name: Record step completion
        if: success()
        run: |
          yq e '.status.steps[] | select(.name == "store-secrets") | .status = "completed"' \
            -i "tenant-registry/applications/${{ env.APP_NAME }}.yaml"
          yq e '.status.steps[] | select(.name == "store-secrets") | .completed-at = now' \
            -i "tenant-registry/applications/${{ env.APP_NAME }}.yaml"

      - name: Record step failure
        if: failure()
        run: |
          yq e '.status.steps[] | select(.name == "store-secrets") | .status = "failed"' \
            -i "tenant-registry/applications/${{ env.APP_NAME }}.yaml"
          yq e '.status.steps[] | select(.name == "store-secrets") | .retry-count += 1' \
            -i "tenant-registry/applications/${{ env.APP_NAME }}.yaml"
```

#### 4. Compensation (Rollback) Actions

When a step fails, you may need to clean up:

```yaml
# .github/workflows/provision-with-compensation.yaml
jobs:
  provision:
    runs-on: ubuntu-latest
    steps:
      - name: Create resource group
        id: rg
        run: ./scripts/create-resource-group.sh

      - name: Provision database
        id: db
        run: ./scripts/provision-database.sh

      - name: Create Key Vault
        id: kv
        run: ./scripts/create-keyvault.sh

      - name: Store secrets
        id: secrets
        run: ./scripts/store-secrets.sh

      # Compensation: if secrets fail, clean up Key Vault
      - name: Compensate - Delete Key Vault
        if: failure() && steps.kv.outcome == 'success' && steps.secrets.outcome == 'failure'
        run: |
          echo "Cleaning up Key Vault due to secrets failure..."
          az keyvault delete --name "${{ env.KEYVAULT_NAME }}"

      # Compensation: if any Azure step fails, clean up resource group
      - name: Compensate - Delete Resource Group
        if: failure() && steps.rg.outcome == 'success'
        run: |
          echo "Cleaning up resource group due to failure..."
          az group delete --name "${{ env.RESOURCE_GROUP }}" --yes --no-wait
```

#### 5. Manual Recovery Procedures

Document and provide tools for manual recovery:

```bash
#!/bin/bash
# scripts/resume-provisioning.sh
# Resume a failed provisioning from the last successful step

APP_NAME=$1
REGISTRY_FILE="tenant-registry/applications/${APP_NAME}.yaml"

# Find the first pending or failed step
RESUME_FROM=$(yq e '.status.steps[] | select(.status == "pending" or .status == "failed") | .name' "$REGISTRY_FILE" | head -1)

echo "Resuming provisioning for $APP_NAME from step: $RESUME_FROM"

case $RESUME_FROM in
  "store-secrets")
    ./scripts/store-secrets.sh "$APP_NAME"
    ./scripts/create-namespace.sh "$APP_NAME"
    ./scripts/configure-rbac.sh "$APP_NAME"
    ./scripts/deploy-argocd-app.sh "$APP_NAME"
    ./scripts/send-notification.sh "$APP_NAME"
    ;;
  "create-namespace")
    ./scripts/create-namespace.sh "$APP_NAME"
    ./scripts/configure-rbac.sh "$APP_NAME"
    ./scripts/deploy-argocd-app.sh "$APP_NAME"
    ./scripts/send-notification.sh "$APP_NAME"
    ;;
  # ... etc
esac

# Update status
yq e '.status.phase = "active"' -i "$REGISTRY_FILE"
```

### Advanced: Using a Workflow Engine

For complex provisioning, consider a dedicated workflow engine:

```yaml
# Using Argo Workflows for complex provisioning
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: onboard-app-
spec:
  entrypoint: onboard
  arguments:
    parameters:
      - name: app-name
        value: "my-app"

  templates:
    - name: onboard
      dag:
        tasks:
          - name: validate
            template: validate-config
            arguments:
              parameters:
                - name: app-name
                  value: "{{workflow.parameters.app-name}}"

          - name: create-rg
            template: create-resource-group
            dependencies: [validate]

          - name: provision-db
            template: provision-database
            dependencies: [create-rg]

          - name: create-kv
            template: create-keyvault
            dependencies: [create-rg]

          - name: store-secrets
            template: store-secrets
            dependencies: [create-kv, provision-db]

          - name: create-ns
            template: create-namespace
            dependencies: [validate]

          - name: configure-rbac
            template: configure-rbac
            dependencies: [create-ns]

          - name: deploy-argocd
            template: deploy-argocd-app
            dependencies: [configure-rbac, store-secrets]

          - name: notify
            template: send-notification
            dependencies: [deploy-argocd]

    - name: validate-config
      container:
        image: platform-tools:latest
        command: [./scripts/validate-config.sh]
        args: ["{{inputs.parameters.app-name}}"]
      inputs:
        parameters:
          - name: app-name
      retryStrategy:
        limit: 2

    - name: provision-database
      container:
        image: platform-tools:latest
        command: [./scripts/provision-database.sh]
        args: ["{{inputs.parameters.app-name}}"]
      inputs:
        parameters:
          - name: app-name
      retryStrategy:
        limit: 3
        retryPolicy: "Always"
        backoff:
          duration: "30s"
          factor: 2
          maxDuration: "5m"

---

## Shared Component Management

### The Challenge

Your platform has components shared across multiple tenants:

| Component | Shared Across | Concerns |
|-----------|---------------|----------|
| AKS Cluster | All tenants in cluster | Capacity, node pools, upgrades |
| ArgoCD | All tenants | Application limits, RBAC |
| Linkerd | All tenants in cluster | Control plane resources |
| Azure Front Door | All tenants with custom domains | Route configuration |
| Container Registry | All tenants | Storage, access control |
| DNS Zone | All tenants | Record management |

### Tracking Shared Components

```yaml
# tenant-registry/shared/aks-prod-01.yaml
apiVersion: platform.company.com/v1
kind: SharedComponent
metadata:
  name: aks-prod-01
  type: kubernetes-cluster
spec:
  capacity:
    max-namespaces: 100
    max-total-cpu: "500"
    max-total-memory: "1000Gi"
    reserved-system-cpu: "20"
    reserved-system-memory: "40Gi"

  scaling:
    min-nodes: 5
    max-nodes: 50
    scale-up-threshold: 0.7    # Add nodes at 70% utilization
    scale-down-threshold: 0.3  # Remove nodes at 30% utilization

  maintenance:
    upgrade-window: "Saturday 02:00-06:00 UTC"
    auto-upgrade: true
    auto-upgrade-channel: stable

status:
  current-namespaces: 45
  current-nodes: 18
  allocated-cpu: "180"
  allocated-memory: "360Gi"
  utilization:
    cpu: 0.45
    memory: 0.42
  tenants:
    - payments-api
    - orders-api
    - notifications-service
    # ... list of all tenants on this cluster
```

### Preventing Race Conditions

When multiple provisioning operations run in parallel:

```yaml
# .github/workflows/provision.yaml
concurrency:
  # Only one provisioning per cluster at a time
  group: provision-${{ matrix.cluster }}
  cancel-in-progress: false
```

For Terraform, use state locking:

```hcl
# terraform/applications/my-app/backend.tf
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstate"
    container_name       = "tfstate"
    key                  = "applications/my-app.tfstate"

    # Enable state locking
    use_azuread_auth = true
  }
}
```

### Capacity Planning

```bash
#!/bin/bash
# scripts/check-cluster-capacity.sh

CLUSTER=$1
APP_CONFIG=$2

CLUSTER_FILE="tenant-registry/clusters/${CLUSTER}.yaml"
APP_FILE="tenant-registry/applications/${APP_CONFIG}.yaml"

# Get current allocation
current_namespaces=$(yq e '.status.current-namespaces' "$CLUSTER_FILE")
max_namespaces=$(yq e '.spec.capacity.max-namespaces' "$CLUSTER_FILE")

current_cpu=$(yq e '.status.allocated-cpu' "$CLUSTER_FILE" | tr -d '"')
max_cpu=$(yq e '.spec.capacity.max-total-cpu' "$CLUSTER_FILE" | tr -d '"')
reserved_cpu=$(yq e '.spec.capacity.reserved-system-cpu' "$CLUSTER_FILE" | tr -d '"')

# Get requested resources from app config
requested_cpu=$(yq e '.spec.infrastructure.namespace.cpu-limit' "$APP_FILE" | tr -d '"')

# Calculate available
available_cpu=$((max_cpu - reserved_cpu - current_cpu))

echo "Cluster: $CLUSTER"
echo "Namespaces: $current_namespaces / $max_namespaces"
echo "CPU: ${current_cpu} / $((max_cpu - reserved_cpu)) (${available_cpu} available)"
echo "Requested CPU: $requested_cpu"

# Check capacity
if [[ $current_namespaces -ge $max_namespaces ]]; then
  echo "ERROR: Cluster has reached maximum namespace limit"
  exit 1
fi

if [[ $requested_cpu -gt $available_cpu ]]; then
  echo "ERROR: Insufficient CPU capacity"
  echo "Consider using a different cluster or reducing resource requests"
  exit 1
fi

echo "Capacity check passed"
```

### Updating Shared Components

When adding a new tenant requires shared component updates:

```bash
#!/bin/bash
# scripts/update-shared-components.sh

APP_NAME=$1
APP_FILE="tenant-registry/applications/${APP_NAME}.yaml"

# Check if app needs custom domain (requires Azure Front Door update)
custom_domain=$(yq e '.spec.networking.ingress.host' "$APP_FILE")
if [[ -n "$custom_domain" && "$custom_domain" != "null" ]]; then
  echo "Adding custom domain to Azure Front Door..."

  # Add DNS record
  az network dns record-set cname set-record \
    --resource-group rg-dns \
    --zone-name company.com \
    --record-set-name "${custom_domain%%.*}" \
    --cname "platform.azurefd.net"

  # Add Front Door route
  az afd route create \
    --resource-group rg-frontdoor \
    --profile-name platform-fd \
    --endpoint-name platform-endpoint \
    --route-name "${APP_NAME}-route" \
    --origin-group platform-origins \
    --https-redirect Enabled \
    --custom-domains "$custom_domain"
fi

# Update ArgoCD project if needed
team=$(yq e '.spec.owner.team' "$APP_FILE")
if ! kubectl get appproject "$team" -n argocd-system &> /dev/null; then
  echo "Creating ArgoCD project for team: $team"
  ./scripts/create-argocd-project.sh "$team"
fi

# Update cluster tenant list
cluster=$(yq e '.spec.deployment.cluster' "$APP_FILE")
yq e ".status.tenants += [\"${APP_NAME}\"]" -i "tenant-registry/clusters/${cluster}.yaml"
yq e '.status.current-namespaces += 1' -i "tenant-registry/clusters/${cluster}.yaml"
```

---

## Reliability

### Why Control Plane Reliability Matters

Control plane outages can:

- Block new application onboarding
- Prevent configuration changes
- Disrupt billing and cost tracking
- Block security incident response
- Prevent scaling operations

### Defining Service Level Objectives (SLOs)

```yaml
# docs/slo/control-plane-slo.yaml
control-plane:
  availability:
    target: 99.9%  # ~8.7 hours downtime per year
    measurement: |
      Percentage of time that:
      - GitHub Actions can execute workflows
      - Terraform can access state and apply changes
      - ArgoCD can sync applications

  onboarding-latency:
    target: p95 < 15 minutes
    measurement: |
      Time from PR merge to application ready state

  recovery-time:
    target: RTO < 1 hour
    measurement: |
      Time to restore control plane functionality after incident

  recovery-point:
    target: RPO < 1 hour
    measurement: |
      Maximum data loss in Terraform state and tenant registry
```

### High Availability Strategies

#### 1. Terraform State Protection

```hcl
# terraform/shared/terraform-state/main.tf

# Primary state storage
resource "azurerm_storage_account" "tfstate_primary" {
  name                     = "stterraformstateprimary"
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = "eastus2"
  account_tier             = "Standard"
  account_replication_type = "GRS"  # Geo-redundant

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }
}

# State file backup to secondary region
resource "azurerm_storage_account" "tfstate_secondary" {
  name                     = "stterraformstatesecondary"
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = "westus2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Object replication for disaster recovery
resource "azurerm_storage_object_replication" "tfstate" {
  source_storage_account_id      = azurerm_storage_account.tfstate_primary.id
  destination_storage_account_id = azurerm_storage_account.tfstate_secondary.id

  rules {
    source_container_name      = "tfstate"
    destination_container_name = "tfstate-replica"
  }
}
```

#### 2. ArgoCD High Availability

```yaml
# argocd/config/argocd-ha.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmd-params-cm
  namespace: argocd-system
data:
  # Run multiple replicas
  controller.replicas: "2"
  server.replicas: "3"
  reposerver.replicas: "2"

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argocd-server
  namespace: argocd-system
spec:
  replicas: 3
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app.kubernetes.io/name: argocd-server
              topologyKey: kubernetes.io/hostname
```

#### 3. GitHub Actions Self-Hosted Runners

```yaml
# For critical workflows, use self-hosted runners as backup
# kubernetes/platform/github-runners.yaml
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: platform-runners
  namespace: github-runners
spec:
  replicas: 3
  template:
    spec:
      repository: company/platform-control-plane
      labels:
        - self-hosted
        - platform
      resources:
        limits:
          cpu: "2"
          memory: "4Gi"
```

```yaml
# .github/workflows/critical-provision.yaml
jobs:
  provision:
    runs-on: [self-hosted, platform]  # Use self-hosted runners
    # Fallback to GitHub-hosted if self-hosted unavailable
    # runs-on: ${{ github.event.inputs.use_self_hosted == 'true' && 'self-hosted' || 'ubuntu-latest' }}
```

### Disaster Recovery

#### Backup Strategy

```bash
#!/bin/bash
# scripts/backup-control-plane.sh
# Run daily via scheduled workflow

BACKUP_DATE=$(date +%Y%m%d)
BACKUP_CONTAINER="control-plane-backups"

# 1. Backup tenant registry (Git is the backup, but also archive)
tar -czf "/tmp/tenant-registry-${BACKUP_DATE}.tar.gz" tenant-registry/
az storage blob upload \
  --account-name "$BACKUP_STORAGE_ACCOUNT" \
  --container-name "$BACKUP_CONTAINER" \
  --name "tenant-registry/tenant-registry-${BACKUP_DATE}.tar.gz" \
  --file "/tmp/tenant-registry-${BACKUP_DATE}.tar.gz"

# 2. Backup Terraform state files
az storage blob download-batch \
  --account-name "$TFSTATE_STORAGE_ACCOUNT" \
  --source tfstate \
  --destination /tmp/tfstate-backup/

tar -czf "/tmp/tfstate-${BACKUP_DATE}.tar.gz" /tmp/tfstate-backup/
az storage blob upload \
  --account-name "$BACKUP_STORAGE_ACCOUNT" \
  --container-name "$BACKUP_CONTAINER" \
  --name "tfstate/tfstate-${BACKUP_DATE}.tar.gz" \
  --file "/tmp/tfstate-${BACKUP_DATE}.tar.gz"

# 3. Backup ArgoCD configuration
kubectl get applications,appprojects -n argocd-system -o yaml > "/tmp/argocd-${BACKUP_DATE}.yaml"
az storage blob upload \
  --account-name "$BACKUP_STORAGE_ACCOUNT" \
  --container-name "$BACKUP_CONTAINER" \
  --name "argocd/argocd-${BACKUP_DATE}.yaml" \
  --file "/tmp/argocd-${BACKUP_DATE}.yaml"

# 4. Retention: Keep 30 days of backups
az storage blob delete-batch \
  --account-name "$BACKUP_STORAGE_ACCOUNT" \
  --source "$BACKUP_CONTAINER" \
  --if-unmodified-since "$(date -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)"
```

#### Recovery Procedure

```bash
#!/bin/bash
# scripts/restore-control-plane.sh

RESTORE_DATE=$1  # e.g., 20240620

echo "=== Control Plane Recovery Procedure ==="
echo "Restoring from: $RESTORE_DATE"

# 1. Restore tenant registry
echo "Step 1: Restoring tenant registry..."
az storage blob download \
  --account-name "$BACKUP_STORAGE_ACCOUNT" \
  --container-name "control-plane-backups" \
  --name "tenant-registry/tenant-registry-${RESTORE_DATE}.tar.gz" \
  --file "/tmp/tenant-registry-restore.tar.gz"

tar -xzf "/tmp/tenant-registry-restore.tar.gz" -C /tmp/
# Review and apply via Git PR

# 2. Restore Terraform state
echo "Step 2: Restoring Terraform state..."
az storage blob download \
  --account-name "$BACKUP_STORAGE_ACCOUNT" \
  --container-name "control-plane-backups" \
  --name "tfstate/tfstate-${RESTORE_DATE}.tar.gz" \
  --file "/tmp/tfstate-restore.tar.gz"

# CAUTION: Only restore state if current state is corrupted
# tar -xzf "/tmp/tfstate-restore.tar.gz" -C /tmp/
# az storage blob upload-batch --account-name "$TFSTATE_STORAGE_ACCOUNT" ...

# 3. Restore ArgoCD
echo "Step 3: Restoring ArgoCD configuration..."
az storage blob download \
  --account-name "$BACKUP_STORAGE_ACCOUNT" \
  --container-name "control-plane-backups" \
  --name "argocd/argocd-${RESTORE_DATE}.yaml" \
  --file "/tmp/argocd-restore.yaml"

kubectl apply -f /tmp/argocd-restore.yaml

echo "=== Recovery Complete ==="
echo "Please verify:"
echo "  - Tenant registry contents"
echo "  - Terraform state integrity (terraform plan)"
echo "  - ArgoCD applications syncing"
```

---

## Security

### Threat Model

Your control plane is a high-value target:

| Threat | Impact | Mitigation |
|--------|--------|------------|
| Compromised GitHub token | Full infrastructure access | Federated identity, short-lived tokens |
| Terraform state exposure | Secrets leaked | Encrypted state, restricted access |
| Malicious PR merged | Arbitrary infrastructure changes | Required reviews, CODEOWNERS |
| ArgoCD compromise | Deploy malicious workloads | RBAC, network policies |
| Insider threat | Data exfiltration, sabotage | Audit logging, least privilege |

### Identity and Access Management

#### 1. Federated Identity (No Secrets)

```yaml
# .github/workflows/provision.yaml
jobs:
  provision:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # Required for OIDC
      contents: read

    steps:
      - name: Azure Login (Federated)
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
          # No client-secret needed!
```

```hcl
# terraform/shared/github-identity/main.tf

# Create federated credential for GitHub Actions
resource "azuread_application" "github_actions" {
  display_name = "GitHub Actions - Platform Control Plane"
}

resource "azuread_service_principal" "github_actions" {
  application_id = azuread_application.github_actions.application_id
}

resource "azuread_application_federated_identity_credential" "github" {
  application_object_id = azuread_application.github_actions.object_id
  display_name          = "github-actions-main"
  audiences             = ["api://AzureADTokenExchange"]
  issuer                = "https://token.actions.githubusercontent.com"
  subject               = "repo:company/platform-control-plane:ref:refs/heads/main"
}

# Separate credential for PRs (with reduced permissions)
resource "azuread_application_federated_identity_credential" "github_pr" {
  application_object_id = azuread_application.github_actions.object_id
  display_name          = "github-actions-pr"
  audiences             = ["api://AzureADTokenExchange"]
  issuer                = "https://token.actions.githubusercontent.com"
  subject               = "repo:company/platform-control-plane:pull_request"
}
```

#### 2. Least Privilege Roles

```hcl
# terraform/shared/rbac/main.tf

# Role for provisioning workflows (main branch)
resource "azurerm_role_definition" "platform_provisioner" {
  name        = "Platform Provisioner"
  scope       = data.azurerm_subscription.current.id
  description = "Can provision platform resources"

  permissions {
    actions = [
      # Resource groups
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Resources/subscriptions/resourceGroups/write",
      "Microsoft.Resources/subscriptions/resourceGroups/delete",

      # PostgreSQL
      "Microsoft.DBforPostgreSQL/flexibleServers/*",

      # Key Vault
      "Microsoft.KeyVault/vaults/*",

      # Storage
      "Microsoft.Storage/storageAccounts/*",

      # AKS (limited)
      "Microsoft.ContainerService/managedClusters/read",
      "Microsoft.ContainerService/managedClusters/listClusterUserCredential/action",
    ]

    not_actions = [
      # Cannot modify AKS cluster itself
      "Microsoft.ContainerService/managedClusters/write",
      "Microsoft.ContainerService/managedClusters/delete",
    ]
  }
}

# Role for PR validation (read-only)
resource "azurerm_role_definition" "platform_reader" {
  name        = "Platform Reader"
  scope       = data.azurerm_subscription.current.id
  description = "Read-only access for PR validation"

  permissions {
    actions = [
      "*/read",
    ]
  }
}
```

#### 3. Required Reviews and CODEOWNERS

```
# .github/CODEOWNERS

# All changes require platform team review
* @company/platform-team

# Tenant registry changes also need security review for tier-1 apps
tenant-registry/applications/*tier-1* @company/platform-team @company/security-team

# Terraform modules require senior review
terraform/modules/ @company/platform-seniors

# Workflows require security review
.github/workflows/ @company/platform-team @company/security-team
```

```yaml
# .github/branch-protection.yaml (for reference)
# Configure via GitHub UI or API

branches:
  main:
    protection:
      required_pull_request_reviews:
        required_approving_review_count: 2
        dismiss_stale_reviews: true
        require_code_owner_reviews: true
      required_status_checks:
        strict: true
        contexts:
          - validate
          - security-scan
      enforce_admins: true
      restrictions:
        users: []
        teams: [platform-team]
```

### Secrets Management

#### 1. Never Store Secrets in Git

```yaml
# BAD: Secrets in tenant registry
spec:
  database:
    connection-string: "Host=mydb;Password=secret123"  # NEVER DO THIS

# GOOD: Reference to Key Vault
spec:
  database:
    connection-string-secret:
      keyvault: payments-kv
      secret-name: db-connection-string
```

#### 2. Terraform Secret Handling

```hcl
# terraform/modules/azure-postgresql/main.tf

# Generate random password
resource "random_password" "admin" {
  length  = 32
  special = true
}

# Store in Key Vault (not in state)
resource "azurerm_key_vault_secret" "db_password" {
  name         = "${var.app_name}-db-password"
  value        = random_password.admin.result
  key_vault_id = var.keyvault_id

  # Ensure secret is created before database
  lifecycle {
    create_before_destroy = true
  }
}

# Use Key Vault reference in database
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = var.server_name
  administrator_login    = var.admin_username
  administrator_password = random_password.admin.result

  # ... other config
}

# Output only the secret reference, not the value
output "connection_string_secret" {
  value = {
    keyvault    = var.keyvault_name
    secret_name = azurerm_key_vault_secret.db_password.name
  }
}
```

### Audit Logging

```yaml
# .github/workflows/audit-log.yaml
name: Audit Log

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Log changes
        run: |
          # Create audit record
          cat >> audit.json << EOF
          {
            "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
            "event_type": "${{ github.event_name }}",
            "actor": "${{ github.actor }}",
            "ref": "${{ github.ref }}",
            "sha": "${{ github.sha }}",
            "workflow": "${{ github.workflow }}",
            "changes": $(git diff --name-only HEAD~1 HEAD | jq -R -s -c 'split("\n") | map(select(length > 0))')
          }
          EOF

      - name: Send to audit system
        run: |
          # Send to Azure Log Analytics or your SIEM
          az monitor log-analytics workspace invoke-query \
            --workspace "${{ secrets.LOG_ANALYTICS_WORKSPACE }}" \
            --analytics-query "..." \
            --custom-logs audit.json
```

### Network Security

```yaml
# kubernetes/platform/network-policies.yaml

# Isolate control plane from workloads
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: platform-system-isolation
  namespace: platform-system
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Only allow from other platform namespaces
    - from:
        - namespaceSelector:
            matchLabels:
              platform.company.com/type: system
  egress:
    # Allow to Azure APIs
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
      ports:
        - protocol: TCP
          port: 443
    # Allow to Kubernetes API
    - to:
        - ipBlock:
            cidr: 10.0.0.1/32  # Kubernetes API server
      ports:
        - protocol: TCP
          port: 443

---

## Telemetry & Consumption Tracking

### Resource Tagging Strategy

Consistent tagging enables cost allocation and resource tracking:

```hcl
# terraform/modules/common/tags.tf

locals {
  common_tags = {
    # Required tags
    "platform.company.com/managed-by" = "platform-control-plane"
    "platform.company.com/application" = var.app_name
    "platform.company.com/team"        = var.team
    "platform.company.com/cost-center" = var.cost_center
    "platform.company.com/environment" = var.environment

    # Optional tags
    "platform.company.com/tier"        = var.tier
    "platform.company.com/created-at"  = timestamp()
    "platform.company.com/created-by"  = "github-actions"
  }
}

# Usage in any Azure resource
resource "azurerm_resource_group" "app" {
  name     = "rg-${var.app_name}-${var.environment}"
  location = var.location
  tags     = local.common_tags
}
```

### Kubernetes Labels and Annotations

```yaml
# kubernetes/base/namespace/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: {{ .namespace }}
  labels:
    # Standard Kubernetes labels
    app.kubernetes.io/name: {{ .app_name }}
    app.kubernetes.io/managed-by: platform-control-plane
    app.kubernetes.io/part-of: {{ .team }}

    # Platform labels
    platform.company.com/team: {{ .team }}
    platform.company.com/tier: {{ .tier }}
    platform.company.com/cost-center: {{ .cost_center }}
    platform.company.com/environment: {{ .environment }}

  annotations:
    platform.company.com/owner: {{ .owner_email }}
    platform.company.com/slack-channel: {{ .slack_channel }}
    platform.company.com/created-at: {{ now | date "2006-01-02T15:04:05Z" }}
```

### Cost Allocation Dashboard

```bash
#!/bin/bash
# scripts/generate-cost-report.sh

# Generate monthly cost report per team

MONTH=${1:-$(date -d "last month" +%Y-%m)}
START_DATE="${MONTH}-01"
END_DATE=$(date -d "${START_DATE} +1 month -1 day" +%Y-%m-%d)

echo "# Cost Report: $MONTH"
echo ""

# Azure costs by team tag
echo "## Azure Resource Costs"
echo ""
echo "| Team | Resource Type | Cost |"
echo "|------|---------------|------|"

az cost management query \
  --type Usage \
  --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}" \
  --timeframe Custom \
  --time-period start="${START_DATE}" end="${END_DATE}" \
  --dataset-aggregation '{"totalCost":{"name":"PreTaxCost","function":"Sum"}}' \
  --dataset-grouping name="team" type="TagKey" \
  --dataset-grouping name="ResourceType" type="Dimension" \
  -o json | \
  jq -r '.properties.rows[] | "| \(.[0]) | \(.[1]) | $\(.[2] | tonumber | . * 100 | round / 100) |"'

echo ""
echo "## Kubernetes Resource Usage"
echo ""

# Query Prometheus for namespace resource usage
for cluster in $(yq e '.metadata.name' tenant-registry/clusters/*.yaml); do
  echo "### Cluster: $cluster"
  echo ""
  echo "| Namespace | Team | CPU (cores) | Memory (GB) | Pods |"
  echo "|-----------|------|-------------|-------------|------|"

  # Get metrics from Prometheus
  curl -s "http://prometheus.${cluster}.internal/api/v1/query" \
    --data-urlencode "query=sum(namespace:container_cpu_usage_seconds_total:sum_rate) by (namespace)" | \
    jq -r '.data.result[] | "| \(.metric.namespace) | - | \(.value[1] | tonumber | . * 100 | round / 100) | - | - |"'
done
```

### Usage Metrics Collection

```yaml
# kubernetes/platform/prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: platform-usage-metrics
  namespace: monitoring
spec:
  groups:
    - name: platform.usage
      interval: 5m
      rules:
        # CPU usage per namespace (averaged over 1 hour)
        - record: platform:namespace_cpu_usage:avg1h
          expr: |
            avg_over_time(
              sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (namespace)
            [1h:5m])

        # Memory usage per namespace (averaged over 1 hour)
        - record: platform:namespace_memory_usage:avg1h
          expr: |
            avg_over_time(
              sum(container_memory_working_set_bytes{container!=""}) by (namespace)
            [1h:5m])

        # Request count per namespace (from Linkerd)
        - record: platform:namespace_request_count:sum1h
          expr: |
            sum(increase(request_total[1h])) by (namespace)

        # Cost estimation (CPU * rate + Memory * rate)
        - record: platform:namespace_estimated_cost:hourly
          expr: |
            (platform:namespace_cpu_usage:avg1h * 0.05) +
            (platform:namespace_memory_usage:avg1h / 1024 / 1024 / 1024 * 0.01)

    - name: platform.quotas
      interval: 1m
      rules:
        # Quota utilization alerts
        - alert: NamespaceQuotaNearLimit
          expr: |
            kube_resourcequota{type="used"} / kube_resourcequota{type="hard"} > 0.8
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "Namespace {{ $labels.namespace }} is using >80% of quota"
            description: "Resource {{ $labels.resource }} is at {{ $value | humanizePercentage }}"

        - alert: NamespaceQuotaExceeded
          expr: |
            kube_resourcequota{type="used"} / kube_resourcequota{type="hard"} > 0.95
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Namespace {{ $labels.namespace }} quota nearly exhausted"
```

---

## Terraform Module Patterns

### Module: Azure PostgreSQL

```hcl
# terraform/modules/azure-postgresql/main.tf

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Generate admin password
resource "random_password" "admin" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = var.server_name
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = var.postgresql_version
  administrator_login    = var.admin_username
  administrator_password = random_password.admin.result

  storage_mb = var.storage_mb
  sku_name   = var.sku_name

  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup

  zone = var.availability_zone

  tags = var.tags

  lifecycle {
    prevent_destroy = true  # Prevent accidental deletion
  }
}

# Database
resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.main.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# Firewall rule for Azure services
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Firewall rule for AKS
resource "azurerm_postgresql_flexible_server_firewall_rule" "aks" {
  count            = length(var.aks_outbound_ips)
  name             = "AllowAKS-${count.index}"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = var.aks_outbound_ips[count.index]
  end_ip_address   = var.aks_outbound_ips[count.index]
}

# Store password in Key Vault
resource "azurerm_key_vault_secret" "db_password" {
  name         = "${var.app_name}-db-password"
  value        = random_password.admin.result
  key_vault_id = var.keyvault_id

  content_type = "password"

  tags = var.tags
}

# Store connection string in Key Vault
resource "azurerm_key_vault_secret" "connection_string" {
  name         = "${var.app_name}-db-connection-string"
  value        = "Host=${azurerm_postgresql_flexible_server.main.fqdn};Database=${var.database_name};Username=${var.admin_username};Password=${random_password.admin.result};SSL Mode=Require"
  key_vault_id = var.keyvault_id

  content_type = "connection-string"

  tags = var.tags
}

# Diagnostic settings
resource "azurerm_monitor_diagnostic_setting" "postgresql" {
  name                       = "diag-${var.server_name}"
  target_resource_id         = azurerm_postgresql_flexible_server.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "PostgreSQLLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
```

```hcl
# terraform/modules/azure-postgresql/variables.tf

variable "server_name" {
  description = "Name of the PostgreSQL server"
  type        = string
}

variable "app_name" {
  description = "Application name for naming secrets"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "postgresql_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15"
}

variable "admin_username" {
  description = "Administrator username"
  type        = string
  default     = "pgadmin"
}

variable "database_name" {
  description = "Name of the database to create"
  type        = string
}

variable "sku_name" {
  description = "SKU name (e.g., GP_Standard_D2s_v3)"
  type        = string
  default     = "GP_Standard_D2s_v3"
}

variable "storage_mb" {
  description = "Storage size in MB"
  type        = number
  default     = 32768  # 32 GB
}

variable "backup_retention_days" {
  description = "Backup retention in days"
  type        = number
  default     = 7
}

variable "geo_redundant_backup" {
  description = "Enable geo-redundant backups"
  type        = bool
  default     = false
}

variable "availability_zone" {
  description = "Availability zone"
  type        = string
  default     = "1"
}

variable "keyvault_id" {
  description = "Key Vault ID for storing secrets"
  type        = string
}

variable "aks_outbound_ips" {
  description = "AKS outbound IP addresses for firewall rules"
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostics"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
```

```hcl
# terraform/modules/azure-postgresql/outputs.tf

output "server_id" {
  description = "PostgreSQL server ID"
  value       = azurerm_postgresql_flexible_server.main.id
}

output "server_fqdn" {
  description = "PostgreSQL server FQDN"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "database_name" {
  description = "Database name"
  value       = azurerm_postgresql_flexible_server_database.main.name
}

output "admin_username" {
  description = "Administrator username"
  value       = azurerm_postgresql_flexible_server.main.administrator_login
}

output "connection_string_secret" {
  description = "Key Vault secret reference for connection string"
  value = {
    keyvault_name = var.keyvault_id
    secret_name   = azurerm_key_vault_secret.connection_string.name
  }
}

output "password_secret" {
  description = "Key Vault secret reference for password"
  value = {
    keyvault_name = var.keyvault_id
    secret_name   = azurerm_key_vault_secret.db_password.name
  }
}
```

### Module: ArgoCD Application

```hcl
# terraform/modules/argocd-application/main.tf

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

resource "kubernetes_manifest" "argocd_application" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"

    metadata = {
      name      = var.app_name
      namespace = var.argocd_namespace
      labels = {
        "app.kubernetes.io/name"       = var.app_name
        "app.kubernetes.io/managed-by" = "platform-control-plane"
        "platform.company.com/team"    = var.team
      }
      finalizers = var.cascade_delete ? ["resources-finalizer.argocd.argoproj.io"] : []
    }

    spec = {
      project = var.argocd_project

      source = {
        repoURL        = var.repo_url
        targetRevision = var.target_revision
        path           = var.path

        # Kustomize options
        dynamic "kustomize" {
          for_each = var.use_kustomize ? [1] : []
          content {
            images = var.kustomize_images
          }
        }

        # Helm options
        dynamic "helm" {
          for_each = var.use_helm ? [1] : []
          content {
            releaseName = var.helm_release_name
            valueFiles  = var.helm_value_files
            values      = var.helm_values
          }
        }
      }

      destination = {
        server    = var.destination_server
        namespace = var.destination_namespace
      }

      syncPolicy = var.enable_auto_sync ? {
        automated = {
          prune      = var.auto_prune
          selfHeal   = var.self_heal
          allowEmpty = false
        }
        syncOptions = [
          "CreateNamespace=false",
          "PrunePropagationPolicy=foreground",
          "PruneLast=true"
        ]
        retry = {
          limit = 5
          backoff = {
            duration    = "5s"
            factor      = 2
            maxDuration = "3m"
          }
        }
      } : null

      # Health checks
      ignoreDifferences = var.ignore_differences
    }
  }
}
```

```hcl
# terraform/modules/argocd-application/variables.tf

variable "app_name" {
  description = "Application name"
  type        = string
}

variable "argocd_namespace" {
  description = "ArgoCD namespace"
  type        = string
  default     = "argocd-system"
}

variable "argocd_project" {
  description = "ArgoCD project"
  type        = string
  default     = "default"
}

variable "team" {
  description = "Owning team"
  type        = string
}

variable "repo_url" {
  description = "Git repository URL"
  type        = string
}

variable "target_revision" {
  description = "Git branch, tag, or commit"
  type        = string
  default     = "main"
}

variable "path" {
  description = "Path within repository"
  type        = string
}

variable "destination_server" {
  description = "Kubernetes API server URL"
  type        = string
  default     = "https://kubernetes.default.svc"
}

variable "destination_namespace" {
  description = "Target namespace"
  type        = string
}

variable "enable_auto_sync" {
  description = "Enable automatic sync"
  type        = bool
  default     = true
}

variable "auto_prune" {
  description = "Automatically prune resources"
  type        = bool
  default     = true
}

variable "self_heal" {
  description = "Automatically fix drift"
  type        = bool
  default     = true
}

variable "cascade_delete" {
  description = "Delete resources when application is deleted"
  type        = bool
  default     = true
}

variable "use_kustomize" {
  description = "Use Kustomize"
  type        = bool
  default     = true
}

variable "kustomize_images" {
  description = "Kustomize image overrides"
  type        = list(string)
  default     = []
}

variable "use_helm" {
  description = "Use Helm"
  type        = bool
  default     = false
}

variable "helm_release_name" {
  description = "Helm release name"
  type        = string
  default     = ""
}

variable "helm_value_files" {
  description = "Helm value files"
  type        = list(string)
  default     = []
}

variable "helm_values" {
  description = "Inline Helm values"
  type        = string
  default     = ""
}

variable "ignore_differences" {
  description = "Fields to ignore for drift detection"
  type = list(object({
    group             = string
    kind              = string
    jsonPointers      = optional(list(string))
    jqPathExpressions = optional(list(string))
  }))
  default = []
}
```

---

## GitHub Actions Workflows

### Reusable Workflow: Terraform

```yaml
# .github/workflows/terraform-reusable.yaml
name: Terraform (Reusable)

on:
  workflow_call:
    inputs:
      working_directory:
        required: true
        type: string
      action:
        required: true
        type: string  # plan, apply, destroy
      environment:
        required: false
        type: string
        default: ''
    secrets:
      AZURE_CLIENT_ID:
        required: true
      AZURE_TENANT_ID:
        required: true
      AZURE_SUBSCRIPTION_ID:
        required: true

jobs:
  terraform:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}

    defaults:
      run:
        working-directory: ${{ inputs.working_directory }}

    permissions:
      id-token: write
      contents: read
      pull-requests: write

    steps:
      - uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.6.0

      - name: Terraform Init
        run: terraform init

      - name: Terraform Format Check
        if: inputs.action == 'plan'
        run: terraform fmt -check -recursive

      - name: Terraform Validate
        if: inputs.action == 'plan'
        run: terraform validate

      - name: Terraform Plan
        if: inputs.action == 'plan' || inputs.action == 'apply'
        id: plan
        run: |
          terraform plan -out=tfplan -no-color 2>&1 | tee plan.txt
          echo "plan<<EOF" >> $GITHUB_OUTPUT
          cat plan.txt >> $GITHUB_OUTPUT
          echo "EOF" >> $GITHUB_OUTPUT

      - name: Post Plan to PR
        if: inputs.action == 'plan' && github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const plan = `${{ steps.plan.outputs.plan }}`;
            const truncated = plan.length > 60000 ? plan.substring(0, 60000) + '\n\n... (truncated)' : plan;

            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: `### Terraform Plan: \`${{ inputs.working_directory }}\`

            <details>
            <summary>Show Plan</summary>

            \`\`\`
            ${truncated}
            \`\`\`

            </details>`
            });

      - name: Terraform Apply
        if: inputs.action == 'apply'
        run: terraform apply -auto-approve tfplan

      - name: Terraform Destroy
        if: inputs.action == 'destroy'
        run: terraform destroy -auto-approve
```

### Main Provisioning Workflow

```yaml
# .github/workflows/provision.yaml
name: Provision Application

on:
  push:
    branches: [main]
    paths:
      - 'tenant-registry/applications/*.yaml'
  workflow_dispatch:
    inputs:
      application:
        description: 'Application to provision'
        required: true
        type: string

concurrency:
  group: provision-${{ github.sha }}
  cancel-in-progress: false

jobs:
  detect:
    runs-on: ubuntu-latest
    outputs:
      applications: ${{ steps.detect.outputs.applications }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2

      - name: Detect changed applications
        id: detect
        run: |
          if [[ "${{ github.event_name }}" == "workflow_dispatch" ]]; then
            apps='["${{ inputs.application }}"]'
          else
            apps=$(git diff --name-only --diff-filter=AM HEAD~1 HEAD | \
                   grep '^tenant-registry/applications/' | \
                   xargs -I{} basename {} .yaml | \
                   jq -R -s -c 'split("\n") | map(select(length > 0))')
          fi
          echo "applications=$apps" >> $GITHUB_OUTPUT

  provision:
    needs: detect
    if: needs.detect.outputs.applications != '[]'
    runs-on: ubuntu-latest
    strategy:
      matrix:
        application: ${{ fromJson(needs.detect.outputs.applications) }}
      fail-fast: false
      max-parallel: 3

    steps:
      - uses: actions/checkout@v4

      - name: Read application config
        id: config
        run: |
          APP_FILE="tenant-registry/applications/${{ matrix.application }}.yaml"
          echo "cluster=$(yq e '.spec.deployment.cluster' $APP_FILE)" >> $GITHUB_OUTPUT
          echo "namespace=$(yq e '.spec.deployment.namespace' $APP_FILE)" >> $GITHUB_OUTPUT
          echo "team=$(yq e '.spec.owner.team' $APP_FILE)" >> $GITHUB_OUTPUT

      - name: Generate Terraform configuration
        run: |
          mkdir -p terraform/applications/${{ matrix.application }}
          ./scripts/generate-terraform-vars.sh "${{ matrix.application }}"
          ./scripts/generate-terraform-main.sh "${{ matrix.application }}"

      - name: Terraform Plan
        uses: ./.github/workflows/terraform-reusable.yaml
        with:
          working_directory: terraform/applications/${{ matrix.application }}
          action: plan
        secrets:
          AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
          AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Terraform Apply
        uses: ./.github/workflows/terraform-reusable.yaml
        with:
          working_directory: terraform/applications/${{ matrix.application }}
          action: apply
          environment: production
        secrets:
          AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
          AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Generate Kubernetes manifests
        run: ./scripts/generate-k8s-manifests.sh "${{ matrix.application }}"

      - name: Generate ArgoCD application
        run: ./scripts/generate-argocd-app.sh "${{ matrix.application }}"

      - name: Update status
        run: |
          yq e '.status.phase = "active"' -i "tenant-registry/applications/${{ matrix.application }}.yaml"
          yq e '.status.provisioned-at = now' -i "tenant-registry/applications/${{ matrix.application }}.yaml"

      - name: Commit generated files
        run: |
          git config user.name "Platform Bot"
          git config user.email "platform-bot@company.com"
          git add .
          git commit -m "Provision: ${{ matrix.application }}" || echo "No changes to commit"
          git push

      - name: Notify
        if: always()
        uses: slackapi/slack-github-action@v1
        with:
          channel-id: ${{ secrets.PLATFORM_SLACK_CHANNEL }}
          payload: |
            {
              "text": "Application ${{ matrix.application }} provisioning ${{ job.status }}",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Provisioning ${{ job.status }}*\n• Application: `${{ matrix.application }}`\n• Cluster: `${{ steps.config.outputs.cluster }}`\n• Namespace: `${{ steps.config.outputs.namespace }}`"
                  }
                }
              ]
            }
```

### Drift Detection Workflow

```yaml
# .github/workflows/drift-detection.yaml
name: Drift Detection

on:
  schedule:
    - cron: '0 6 * * *'  # Daily at 6 AM UTC
  workflow_dispatch:

jobs:
  detect-drift:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Check for drift
        id: drift
        run: |
          drift_found=false
          drift_report=""

          for app_dir in terraform/applications/*/; do
            app_name=$(basename "$app_dir")
            echo "Checking drift for: $app_name"

            cd "$app_dir"
            terraform init -backend=true > /dev/null

            # Run plan and check for changes
            if ! terraform plan -detailed-exitcode > /tmp/plan.txt 2>&1; then
              exit_code=$?
              if [[ $exit_code -eq 2 ]]; then
                drift_found=true
                drift_report="${drift_report}\n\n## ${app_name}\n\`\`\`\n$(cat /tmp/plan.txt)\n\`\`\`"
              fi
            fi

            cd - > /dev/null
          done

          echo "drift_found=$drift_found" >> $GITHUB_OUTPUT
          echo "drift_report<<EOF" >> $GITHUB_OUTPUT
          echo -e "$drift_report" >> $GITHUB_OUTPUT
          echo "EOF" >> $GITHUB_OUTPUT

      - name: Create issue for drift
        if: steps.drift.outputs.drift_found == 'true'
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: `Infrastructure Drift Detected - ${new Date().toISOString().split('T')[0]}`,
              body: `## Drift Detection Report\n\nDrift was detected in the following applications:\n${{ steps.drift.outputs.drift_report }}`,
              labels: ['drift', 'infrastructure']
            });

      - name: Notify Slack
        if: steps.drift.outputs.drift_found == 'true'
        uses: slackapi/slack-github-action@v1
        with:
          channel-id: ${{ secrets.PLATFORM_SLACK_CHANNEL }}
          payload: |
            {
              "text": "Infrastructure drift detected!",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Infrastructure Drift Detected*\n\nCheck the GitHub issue for details."
                  }
                }
              ]
            }

---

## ArgoCD Integration

### Multi-Tenancy with ArgoCD Projects

Each team gets an ArgoCD Project that restricts what they can deploy:

```yaml
# argocd/projects/payments-team.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: payments-team
  namespace: argocd-system
spec:
  description: "Payments team applications"

  # Source repositories allowed
  sourceRepos:
    - 'https://github.com/company/payments-*'
    - 'https://github.com/company/shared-charts'

  # Destination clusters and namespaces
  destinations:
    - namespace: 'payments'
      server: https://kubernetes.default.svc
    - namespace: 'payments-*'
      server: https://kubernetes.default.svc

  # Cluster resources the team can manage
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
    - group: networking.k8s.io
      kind: Ingress

  # Namespace resources the team can manage
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'

  # Resources the team cannot manage (even in their namespace)
  namespaceResourceBlacklist:
    - group: ''
      kind: ResourceQuota
    - group: ''
      kind: LimitRange
    - group: networking.k8s.io
      kind: NetworkPolicy

  # Roles within this project
  roles:
    - name: admin
      description: Admin access to payments-team apps
      policies:
        - p, proj:payments-team:admin, applications, *, payments-team/*, allow
      groups:
        - payments-admins

    - name: developer
      description: Developer access (view + sync)
      policies:
        - p, proj:payments-team:developer, applications, get, payments-team/*, allow
        - p, proj:payments-team:developer, applications, sync, payments-team/*, allow
      groups:
        - payments-developers

  # Sync windows (optional)
  syncWindows:
    - kind: deny
      schedule: '0 22 * * 5'  # No deploys Friday 10 PM
      duration: 36h           # Until Sunday 10 AM
      applications:
        - '*'
```

### ApplicationSet for Automatic App Creation

```yaml
# argocd/applicationsets/tenant-apps.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: tenant-applications
  namespace: argocd-system
spec:
  generators:
    # Generate from tenant registry files
    - git:
        repoURL: https://github.com/company/platform-control-plane
        revision: main
        files:
          - path: "tenant-registry/applications/*.yaml"

  template:
    metadata:
      name: '{{ .metadata.name }}'
      namespace: argocd-system
      labels:
        app.kubernetes.io/managed-by: applicationset
        platform.company.com/team: '{{ .spec.owner.team }}'
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: '{{ .spec.owner.team }}'

      source:
        repoURL: '{{ .spec.argocd.repo }}'
        targetRevision: '{{ .spec.argocd.targetRevision | default "main" }}'
        path: '{{ .spec.argocd.path }}'

      destination:
        server: https://kubernetes.default.svc
        namespace: '{{ .spec.deployment.namespace }}'

      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=false
          - PrunePropagationPolicy=foreground
        retry:
          limit: 5
          backoff:
            duration: 5s
            factor: 2
            maxDuration: 3m
```

### ArgoCD Notifications

```yaml
# argocd/config/argocd-notifications-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd-system
data:
  # Slack service
  service.slack: |
    token: $slack-token

  # Templates
  template.app-deployed: |
    message: |
      Application {{.app.metadata.name}} is now {{.app.status.sync.status}}.
      Revision: {{.app.status.sync.revision}}
    slack:
      attachments: |
        [{
          "color": "#18be52",
          "fields": [
            {"title": "Application", "value": "{{.app.metadata.name}}", "short": true},
            {"title": "Namespace", "value": "{{.app.spec.destination.namespace}}", "short": true},
            {"title": "Revision", "value": "{{.app.status.sync.revision | trunc 7}}", "short": true}
          ]
        }]

  template.app-health-degraded: |
    message: |
      Application {{.app.metadata.name}} health is {{.app.status.health.status}}.
    slack:
      attachments: |
        [{
          "color": "#f4c030",
          "fields": [
            {"title": "Application", "value": "{{.app.metadata.name}}", "short": true},
            {"title": "Health", "value": "{{.app.status.health.status}}", "short": true}
          ]
        }]

  # Triggers
  trigger.on-deployed: |
    - when: app.status.sync.status == 'Synced' and app.status.health.status == 'Healthy'
      send: [app-deployed]

  trigger.on-health-degraded: |
    - when: app.status.health.status == 'Degraded'
      send: [app-health-degraded]

  # Subscriptions (default for all apps)
  subscriptions: |
    - recipients:
        - slack:platform-deployments
      triggers:
        - on-deployed
        - on-health-degraded

---
# Per-team notifications via annotations
# kubernetes/applications/payments-api/argocd-application.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: payments-api
  annotations:
    notifications.argoproj.io/subscribe.on-deployed.slack: payments-team
    notifications.argoproj.io/subscribe.on-health-degraded.slack: payments-team
```

---

## Linkerd Service Mesh Policies

### Namespace Authorization Policy

Control which namespaces can communicate:

```yaml
# kubernetes/applications/payments-api/linkerd-policy.yaml

# Server definition for the payments API
apiVersion: policy.linkerd.io/v1beta2
kind: Server
metadata:
  name: payments-api
  namespace: payments
spec:
  podSelector:
    matchLabels:
      app: payments-api
  port: http
  proxyProtocol: HTTP/2

---
# Allow traffic from orders namespace
apiVersion: policy.linkerd.io/v1alpha1
kind: AuthorizationPolicy
metadata:
  name: allow-orders
  namespace: payments
spec:
  targetRef:
    group: policy.linkerd.io
    kind: Server
    name: payments-api
  requiredAuthenticationRefs:
    - name: orders-namespace
      kind: MeshTLSAuthentication
      group: policy.linkerd.io

---
# Define the orders namespace identity
apiVersion: policy.linkerd.io/v1alpha1
kind: MeshTLSAuthentication
metadata:
  name: orders-namespace
  namespace: payments
spec:
  identities:
    - "*.orders.serviceaccount.identity.linkerd.cluster.local"

---
# Allow traffic from ingress
apiVersion: policy.linkerd.io/v1alpha1
kind: AuthorizationPolicy
metadata:
  name: allow-ingress
  namespace: payments
spec:
  targetRef:
    group: policy.linkerd.io
    kind: Server
    name: payments-api
  requiredAuthenticationRefs:
    - name: ingress-nginx
      kind: MeshTLSAuthentication
      group: policy.linkerd.io

---
apiVersion: policy.linkerd.io/v1alpha1
kind: MeshTLSAuthentication
metadata:
  name: ingress-nginx
  namespace: payments
spec:
  identities:
    - "*.ingress-nginx.serviceaccount.identity.linkerd.cluster.local"
```

### Default Deny Policy

```yaml
# kubernetes/base/linkerd-policy/default-deny.yaml

# Default policy: deny all unauthenticated traffic
apiVersion: policy.linkerd.io/v1beta2
kind: Server
metadata:
  name: default-deny
  namespace: {{ .namespace }}
spec:
  podSelector: {}  # All pods
  port: ""         # All ports
  proxyProtocol: HTTP/2

---
# Only allow traffic from authenticated mesh clients
apiVersion: policy.linkerd.io/v1alpha1
kind: AuthorizationPolicy
metadata:
  name: default-mesh-only
  namespace: {{ .namespace }}
spec:
  targetRef:
    group: policy.linkerd.io
    kind: Server
    name: default-deny
  requiredAuthenticationRefs:
    - name: mesh-tls
      kind: MeshTLSAuthentication
      group: policy.linkerd.io

---
apiVersion: policy.linkerd.io/v1alpha1
kind: MeshTLSAuthentication
metadata:
  name: mesh-tls
  namespace: {{ .namespace }}
spec:
  identityRefs:
    - kind: ServiceAccount
```

### Traffic Split for Canary Deployments

```yaml
# kubernetes/applications/payments-api/traffic-split.yaml
apiVersion: split.smi-spec.io/v1alpha2
kind: TrafficSplit
metadata:
  name: payments-api-canary
  namespace: payments
spec:
  service: payments-api
  backends:
    - service: payments-api-stable
      weight: 900m   # 90%
    - service: payments-api-canary
      weight: 100m   # 10%
```

### Linkerd Policy Generation Script

```bash
#!/bin/bash
# scripts/generate-linkerd-policy.sh

APP_NAME=$1
APP_FILE="tenant-registry/applications/${APP_NAME}.yaml"
OUTPUT_DIR="kubernetes/applications/${APP_NAME}"

namespace=$(yq e '.spec.deployment.namespace' "$APP_FILE")
allowed_namespaces=$(yq e '.spec.networking.allowed-namespaces[]' "$APP_FILE" 2>/dev/null)

cat > "${OUTPUT_DIR}/linkerd-server.yaml" << EOF
apiVersion: policy.linkerd.io/v1beta2
kind: Server
metadata:
  name: ${APP_NAME}
  namespace: ${namespace}
spec:
  podSelector:
    matchLabels:
      app: ${APP_NAME}
  port: http
  proxyProtocol: HTTP/2
EOF

# Generate authorization policies for each allowed namespace
for allowed_ns in $allowed_namespaces; do
  cat >> "${OUTPUT_DIR}/linkerd-authz.yaml" << EOF
---
apiVersion: policy.linkerd.io/v1alpha1
kind: AuthorizationPolicy
metadata:
  name: allow-${allowed_ns}
  namespace: ${namespace}
spec:
  targetRef:
    group: policy.linkerd.io
    kind: Server
    name: ${APP_NAME}
  requiredAuthenticationRefs:
    - name: ${allowed_ns}-identity
      kind: MeshTLSAuthentication
      group: policy.linkerd.io
---
apiVersion: policy.linkerd.io/v1alpha1
kind: MeshTLSAuthentication
metadata:
  name: ${allowed_ns}-identity
  namespace: ${namespace}
spec:
  identities:
    - "*.${allowed_ns}.serviceaccount.identity.linkerd.cluster.local"
EOF
done

echo "Generated Linkerd policies for ${APP_NAME}"
```

---

## Operational Runbooks

### Runbook: Failed Provisioning

```markdown
# Runbook: Failed Application Provisioning

## Symptoms
- Application status is "failed" in tenant registry
- Terraform apply failed
- GitHub Actions workflow failed

## Diagnosis

1. Check workflow logs:
   ```bash
   gh run view <run-id> --log-failed
   ```

2. Check tenant registry status:
   ```bash
   yq e '.status' tenant-registry/applications/<app-name>.yaml
   ```

3. Check Terraform state:
   ```bash
   cd terraform/applications/<app-name>
   terraform init
   terraform plan
   ```

## Resolution

### If Terraform partial apply:

1. Identify which resources were created:
   ```bash
   terraform state list
   ```

2. Option A - Resume provisioning:
   ```bash
   ./scripts/resume-provisioning.sh <app-name>
   ```

3. Option B - Rollback and retry:
   ```bash
   terraform destroy -auto-approve
   # Fix the issue
   terraform apply
   ```

### If Azure resource limit:

1. Check subscription limits:
   ```bash
   az vm list-usage --location eastus2 -o table
   ```

2. Request quota increase or use different region

### If namespace conflict:

1. Check if namespace exists:
   ```bash
   kubectl get namespace <namespace>
   ```

2. If orphaned, clean up manually:
   ```bash
   kubectl delete namespace <namespace>
   ```

## Post-Resolution

1. Update tenant registry status:
   ```bash
   yq e '.status.phase = "active"' -i tenant-registry/applications/<app-name>.yaml
   ```

2. Commit and push changes

3. Notify the team
```

### Runbook: ArgoCD Sync Issues

```markdown
# Runbook: ArgoCD Application Not Syncing

## Symptoms
- Application shows "OutOfSync" or "Unknown"
- Health status is "Degraded" or "Missing"
- Pods not starting

## Diagnosis

1. Check application status:
   ```bash
   argocd app get <app-name>
   ```

2. Check sync status:
   ```bash
   argocd app sync <app-name> --dry-run
   ```

3. Check application events:
   ```bash
   kubectl describe application <app-name> -n argocd-system
   ```

4. Check pod events:
   ```bash
   kubectl get events -n <namespace> --sort-by='.lastTimestamp'
   ```

## Common Issues and Resolutions

### Image pull error:
```bash
# Check image exists
az acr repository show-tags --name <acr-name> --repository <image>

# Check pull secret
kubectl get secret -n <namespace>
```

### Resource quota exceeded:
```bash
# Check quota
kubectl describe resourcequota -n <namespace>

# Adjust in tenant registry and re-provision
```

### Invalid manifest:
```bash
# Validate locally
kubectl apply --dry-run=client -f <manifest>

# Check ArgoCD diff
argocd app diff <app-name>
```

### RBAC issues:
```bash
# Check service account permissions
kubectl auth can-i --as=system:serviceaccount:<namespace>:<sa> <verb> <resource>
```

## Force Sync (Use with caution)

```bash
# Hard refresh
argocd app get <app-name> --hard-refresh

# Force sync with prune
argocd app sync <app-name> --force --prune
```

## Escalation

If issue persists after 30 minutes:
1. Page platform-oncall
2. Create incident in PagerDuty
3. Update status page
```

### Runbook: Cluster Capacity Issues

```markdown
# Runbook: Cluster Capacity Exhausted

## Symptoms
- Pods stuck in Pending
- New namespaces cannot be created
- Autoscaler not adding nodes

## Diagnosis

1. Check node status:
   ```bash
   kubectl get nodes
   kubectl describe nodes | grep -A5 "Allocated resources"
   ```

2. Check cluster autoscaler:
   ```bash
   kubectl logs -n kube-system -l app=cluster-autoscaler --tail=100
   ```

3. Check pending pods:
   ```bash
   kubectl get pods --all-namespaces --field-selector=status.phase=Pending
   ```

## Resolution

### If autoscaler is stuck:

1. Check Azure VM quota:
   ```bash
   az vm list-usage --location eastus2 -o table
   ```

2. Check node pool limits:
   ```bash
   az aks nodepool show --cluster-name <cluster> --name workloads -g <rg>
   ```

3. Increase max nodes if needed:
   ```bash
   az aks nodepool update --cluster-name <cluster> --name workloads -g <rg> --max-count 100
   ```

### If legitimate capacity issue:

1. Update cluster registry:
   ```yaml
   # tenant-registry/clusters/<cluster>.yaml
   spec:
     node-pools:
       - name: workloads
         max-count: 100  # Increase
   ```

2. Apply via Terraform:
   ```bash
   cd terraform/clusters/<cluster>
   terraform apply
   ```

### Emergency: Evict low-priority workloads

```bash
# Identify non-critical namespaces
kubectl get namespaces -l platform.company.com/tier=tier-3

# Scale down temporarily
kubectl scale deployment --all -n <namespace> --replicas=0
```

## Prevention

1. Set up capacity alerts in monitoring
2. Review cluster capacity weekly
3. Plan capacity for upcoming onboardings
```

---

## Checklist & Maturity Model

### Implementation Checklist

#### Phase 1: Foundation
- [ ] Create Git repository structure
- [ ] Define tenant registry schema
- [ ] Set up Terraform backend with state locking
- [ ] Configure Azure federated identity for GitHub Actions
- [ ] Create basic namespace provisioning module
- [ ] Implement PR validation workflow
- [ ] Set up branch protection and CODEOWNERS

#### Phase 2: Core Functionality
- [ ] Implement full onboarding workflow
- [ ] Create Azure resource modules (PostgreSQL, Key Vault, etc.)
- [ ] Set up ArgoCD with projects per team
- [ ] Implement basic Linkerd policies
- [ ] Add Slack notifications
- [ ] Create offboarding workflow
- [ ] Document onboarding process for developers

#### Phase 3: Reliability
- [ ] Set up Terraform state backups
- [ ] Configure ArgoCD HA
- [ ] Implement drift detection
- [ ] Create disaster recovery runbooks
- [ ] Set up monitoring and alerting
- [ ] Define and track SLOs

#### Phase 4: Security
- [ ] Implement least-privilege IAM
- [ ] Set up audit logging
- [ ] Configure network policies
- [ ] Implement secrets rotation
- [ ] Conduct security review
- [ ] Set up vulnerability scanning

#### Phase 5: Scale
- [ ] Implement ApplicationSets
- [ ] Add capacity planning automation
- [ ] Create self-service portal (Backstage)
- [ ] Implement cost allocation reporting
- [ ] Add multi-cluster support
- [ ] Performance optimization

### Maturity Model

| Level | Description | Characteristics |
|-------|-------------|-----------------|
| **Level 1: Manual** | Human-driven provisioning | Scripts run manually, inconsistent processes, no self-service |
| **Level 2: Automated** | Basic automation | GitHub Actions for provisioning, Terraform modules, basic GitOps |
| **Level 3: Self-Service** | Developer autonomy | PR-based onboarding, automatic provisioning, team notifications |
| **Level 4: Governed** | Policy enforcement | Quotas, cost tracking, compliance automation, audit trails |
| **Level 5: Optimized** | Continuous improvement | Capacity prediction, cost optimization, automated remediation |

### Key Metrics to Track

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Onboarding time | < 15 min | Time from PR merge to app ready |
| Provisioning success rate | > 99% | Successful / Total provisioning attempts |
| Drift detection coverage | 100% | Apps with drift checks / Total apps |
| Mean time to recovery | < 1 hour | Time to restore after control plane incident |
| Cost per tenant | Varies | Azure costs / Number of tenants |
| Developer satisfaction | > 4/5 | Quarterly survey |

---

## Conclusion

Building a control plane for your internal developer platform brings the same rigor and patterns used by enterprise SaaS providers to your internal operations. Key takeaways:

1. **Treat the control plane as a product** — It needs reliability, security, and good UX
2. **Use Git as the source of truth** — The tenant registry pattern provides auditability and recoverability
3. **Automate everything** — Manual processes don't scale and introduce inconsistency
4. **Plan for failure** — Idempotent operations, state tracking, and recovery procedures are essential
5. **Security is foundational** — The control plane is highly privileged; protect it accordingly

Start simple and iterate. You don't need everything on day one — begin with basic automation and add governance, observability, and optimization as you scale.

---

## References

- [Microsoft: Control planes in multitenant architecture](https://learn.microsoft.com/en-us/azure/architecture/guide/multitenant/considerations/control-planes)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Linkerd Authorization Policy](https://linkerd.io/2.14/reference/authorization-policy/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Platform Engineering on Kubernetes](https://www.manning.com/books/platform-engineering-on-kubernetes)
- [Backstage.io](https://backstage.io/) — Internal developer portal
```
```
```
```
```

