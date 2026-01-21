# K3s Cluster Networking

This directory contains the networking configuration for the k3s home lab cluster, managed via ArgoCD.

## Components

### MetalLB (Load Balancer)
- **IP Pool**: `10.1.1.230-10.1.1.250`
- **Mode**: L2 Advertisement on `eth1` (home network interface)
- **ArgoCD App**: `cluster-networking`

### CoreDNS Custom Configuration
- **Domain**: `.lab` (internal cluster DNS)
- **Upstream DNS**: Cloudflare `1.1.1.1`
- Applied directly to `kube-system` (not via ArgoCD)

## Network Architecture

```
Home Network (10.1.1.0/24)
├── Router/Gateway: 10.1.1.1
├── Hyper-V Host: 10.1.1.55
├── Linux Workstation: 10.1.1.122
│
├── K3s Nodes (dual NIC - eth1 on home network)
│   ├── k3s-master: 10.1.1.60
│   ├── k3s-worker-1: 10.1.1.61
│   └── k3s-worker-2: 10.1.1.62
│
├── MetalLB LoadBalancer IPs
│   ├── Traefik Ingress: 10.1.1.230
│   └── dnsmasq DNS: 10.1.1.231
│
└── Internal Cluster Network (10.10.10.0/24) - eth0
    ├── k3s-master: 10.10.10.10
    ├── k3s-worker-1: 10.10.10.11
    └── k3s-worker-2: 10.10.10.12
```

## DNS Resolution

### dnsmasq (Network-wide DNS)
- **IP**: `10.1.1.231`
- **Config**: `../dnsmasq/configmap.yaml`
- **ArgoCD App**: `dnsmasq`

Configure your router's DHCP to use `10.1.1.231` as the primary DNS server.

### Current DNS Records

| Hostname | IP | Description |
|----------|-----|-------------|
| traefik.lab | 10.1.1.230 | Traefik ingress controller |
| argocd.lab | 10.1.1.230 | ArgoCD UI |
| workout.lab | 10.1.1.230 | Workout Tracker app |
| k3s-master.lab | 10.1.1.60 | Master node |
| k3s-worker-1.lab | 10.1.1.61 | Worker node 1 |
| k3s-worker-2.lab | 10.1.1.62 | Worker node 2 |

### Adding DNS Records

Edit `../dnsmasq/configmap.yaml`:

```yaml
address=/myapp.lab/10.1.1.230
```

Then commit/push or apply directly:
```bash
kubectl rollout restart deployment dnsmasq -n dns
```

## Traefik Ingress

Traefik is managed by k3s (not ArgoCD). LoadBalancer IP: `10.1.1.230`

### Creating IngressRoutes

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: myapp-route
  namespace: myapp
spec:
  entryPoints:
    - web
  routes:
  - match: Host(`myapp.lab`)
    kind: Rule
    services:
    - name: myapp-service
      port: 80
```

## Files

| File | Description |
|------|-------------|
| `coredns-custom.yaml` | CoreDNS config for in-cluster `.lab` resolution |
| `metallb-config.yaml` | MetalLB IPAddressPool and L2Advertisement |
| `metallb-native.yaml` | MetalLB v0.14.9 manifests |
| `kustomization.yaml` | Kustomize config for ArgoCD |
| `argocd-app.yaml` | ArgoCD Application definition |

## Hyper-V Host Configuration

The k3s VMs run on Hyper-V with dual NICs:
- **eth0**: Internal network (`k8s-internal` switch) - 10.10.10.x
- **eth1**: External network (`HyperVSwitch`) - 10.1.1.x

### VM Network Configuration

Each VM has netplan config at `/etc/netplan/60-external.yaml`:

```yaml
network:
  version: 2
  ethernets:
    eth1:
      addresses:
        - 10.1.1.6X/24  # 60, 61, or 62
```
