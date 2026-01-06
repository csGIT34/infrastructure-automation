#!/bin/bash
#
# Deploy Actions Runner Controller to Local k3s Cluster
# Run this from your workstation with kubectl configured
#

set -e

echo "============================================"
echo "  GitHub Actions Runner Controller Setup"
echo "============================================"
echo ""

# Check prerequisites
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed."; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "helm is required but not installed."; exit 1; }

# Configuration - EDIT THESE
GITHUB_ORG="${GITHUB_ORG:-}"
GITHUB_REPO="${GITHUB_REPO:-infrastructure-automation}"
GITHUB_PAT="${GITHUB_PAT:-}"

# Check required variables
if [ -z "$GITHUB_PAT" ]; then
    echo "Error: GITHUB_PAT environment variable is required"
    echo ""
    echo "Create a Personal Access Token at:"
    echo "  https://github.com/settings/tokens"
    echo ""
    echo "Required scopes: repo, workflow, admin:org (for org runners)"
    echo ""
    echo "Usage:"
    echo "  export GITHUB_PAT=ghp_xxxxxxxxxxxx"
    echo "  export GITHUB_ORG=your-org          # Optional, for org-level runners"
    echo "  export GITHUB_REPO=your-repo        # Default: infrastructure-automation"
    echo "  ./deploy-local-arc.sh"
    exit 1
fi

echo "[1/7] Verifying cluster connection..."
kubectl cluster-info
echo ""

echo "[2/7] Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

echo "Waiting for cert-manager pods..."
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager-webhook -n cert-manager
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager-cainjector -n cert-manager
echo "cert-manager is ready!"
echo ""

echo "[3/7] Adding Helm repository..."
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
helm repo update
echo ""

echo "[4/7] Installing Actions Runner Controller..."
kubectl create namespace actions-runner-system --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install arc \
    actions-runner-controller/actions-runner-controller \
    --namespace actions-runner-system \
    --set authSecret.create=true \
    --set authSecret.github_token="$GITHUB_PAT" \
    --set image.actionsRunnerRepositoryAndTag=summerwind/actions-runner:latest \
    --wait

echo "Waiting for ARC controller..."
kubectl wait --for=condition=Available --timeout=300s deployment/arc-actions-runner-controller -n actions-runner-system
echo "ARC controller is ready!"
echo ""

echo "[5/7] Creating runners namespace..."
kubectl create namespace github-runners --dry-run=client -o yaml | kubectl apply -f -
echo ""

echo "[6/7] Deploying runner deployment..."

# Determine if using org or repo runners
if [ -n "$GITHUB_ORG" ]; then
    RUNNER_SPEC="organization: $GITHUB_ORG"
    echo "Configuring org-level runners for: $GITHUB_ORG"
else
    RUNNER_SPEC="repository: $GITHUB_REPO"
    echo "Configuring repo-level runners for: $GITHUB_REPO"
fi

kubectl apply -f - <<EOF
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: local-runners
  namespace: github-runners
spec:
  replicas: 2
  template:
    spec:
      $RUNNER_SPEC
      labels:
        - self-hosted
        - linux
        - local
        - infrastructure
      env:
        - name: RUNNER_FEATURE_FLAG_EPHEMERAL
          value: "false"
      resources:
        requests:
          cpu: "500m"
          memory: "1Gi"
        limits:
          cpu: "2"
          memory: "4Gi"
      volumeMounts:
        - name: work
          mountPath: /runner/_work
      volumes:
        - name: work
          emptyDir: {}
---
apiVersion: actions.summerwind.dev/v1alpha1
kind: HorizontalRunnerAutoscaler
metadata:
  name: local-runners-autoscaler
  namespace: github-runners
spec:
  scaleTargetRef:
    name: local-runners
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: PercentageRunnersBusy
      scaleUpThreshold: '0.75'
      scaleDownThreshold: '0.25'
      scaleUpFactor: '2'
      scaleDownFactor: '0.5'
EOF

echo ""
echo "[7/7] Waiting for runners to be ready..."
sleep 10

echo ""
echo "============================================"
echo "  Deployment Complete!"
echo "============================================"
echo ""
echo "Runner Status:"
kubectl get runners -n github-runners
echo ""
echo "Runner Pods:"
kubectl get pods -n github-runners
echo ""
echo "Verify in GitHub:"
echo "  Repository -> Settings -> Actions -> Runners"
echo ""
echo "Your workflows can now use:"
echo "  runs-on: [self-hosted, linux, local]"
echo ""
