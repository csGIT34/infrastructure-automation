# dnsmasq DNS Server

Network-wide DNS server for resolving `.lab` domain names, deployed via ArgoCD.

## Overview

- **LoadBalancer IP**: `10.1.1.231`
- **Upstream DNS**: Cloudflare `1.1.1.1`, `1.0.0.1`
- **Local Domain**: `.lab`
- **ArgoCD App**: `dnsmasq`

## Usage

Configure your router's DHCP to hand out `10.1.1.231` as the primary DNS server, or manually configure devices:

```bash
# Linux (temporary)
sudo resolvectl dns enp14s0 10.1.1.231

# Test
nslookup argocd.lab 10.1.1.231
```

## Adding DNS Records

Edit `configmap.yaml` and add entries:

```yaml
# For apps behind Traefik ingress
address=/myapp.lab/10.1.1.230

# For direct IP access
address=/myserver.lab/10.1.1.100
```

Then either:
1. Commit and push (ArgoCD auto-syncs)
2. Or apply directly: `kubectl rollout restart deployment dnsmasq -n dns`

## Current Records

| Hostname | IP | Notes |
|----------|-----|-------|
| traefik.lab | 10.1.1.230 | Traefik ingress |
| argocd.lab | 10.1.1.230 | Via Traefik |
| workout.lab | 10.1.1.230 | Via Traefik |
| k3s-master.lab | 10.1.1.60 | Direct node access |
| k3s-worker-1.lab | 10.1.1.61 | Direct node access |
| k3s-worker-2.lab | 10.1.1.62 | Direct node access |

## Files

| File | Description |
|------|-------------|
| `namespace.yaml` | `dns` namespace |
| `configmap.yaml` | dnsmasq configuration with DNS records |
| `deployment.yaml` | dnsmasq deployment |
| `service.yaml` | LoadBalancer service on 10.1.1.231 |
| `kustomization.yaml` | Kustomize config |
| `argocd-app.yaml` | ArgoCD Application |

## Troubleshooting

```bash
# Check pod status
kubectl get pods -n dns

# Check logs
kubectl logs -n dns -l app=dnsmasq

# Test DNS resolution
nslookup argocd.lab 10.1.1.231

# Restart after config changes
kubectl rollout restart deployment dnsmasq -n dns
```

## Why .lab instead of .local?

The `.local` TLD is reserved for mDNS (multicast DNS / Bonjour / Avahi). Linux systems with systemd-resolved intercept `.local` queries and send them via mDNS instead of regular DNS, causing resolution failures.

Using `.lab` avoids this conflict.
