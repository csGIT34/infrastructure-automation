# ArgoCD Configuration

This directory contains the ArgoCD configuration for the infrastructure-automation platform.

## Installation

### Quick Install (Already Applied)

```bash
# Create namespace and install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Expose via NodePort
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"name": "http", "port": 80, "targetPort": 8080, "nodePort": 30080}, {"name": "https", "port": 443, "targetPort": 8080, "nodePort": 30443}]}}'
```

### Using Kustomize (Recommended for GitOps)

```bash
kubectl apply -k infrastructure/argocd/
```

## Accessing ArgoCD

### Web UI

Access the ArgoCD UI at:
- **HTTP**: http://10.10.10.10:30080
- **HTTPS**: https://10.10.10.10:30443

Or use any worker node IP (10.10.10.11, 10.10.10.12).

### Credentials

- **Username**: `admin`
- **Password**: Get with:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
  ```

### CLI Access

Install the ArgoCD CLI:

```bash
# Linux
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/

# Login
argocd login 10.10.10.10:30443 --insecure --username admin --password <password>
```

## Directory Structure

```
infrastructure/argocd/
├── kustomization.yaml          # Kustomize config for ArgoCD install
├── namespace.yaml              # ArgoCD namespace
├── patches/
│   └── argocd-server-nodeport.yaml  # NodePort exposure
└── apps/
    └── infrastructure-automation.yaml  # App-of-apps pattern
```

## Adding Applications

Create Application manifests in `apps/` directory:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/YOUR_ORG/your-repo.git
    targetRevision: HEAD
    path: k8s/
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Connecting to Private Repositories

```bash
# Add repository via CLI
argocd repo add https://github.com/YOUR_ORG/private-repo.git \
  --username <username> \
  --password <github-pat>

# Or via Kubernetes secret
kubectl create secret generic repo-creds \
  -n argocd \
  --from-literal=url=https://github.com/YOUR_ORG \
  --from-literal=username=<username> \
  --from-literal=password=<github-pat>
kubectl label secret repo-creds -n argocd argocd.argoproj.io/secret-type=repo-creds
```
