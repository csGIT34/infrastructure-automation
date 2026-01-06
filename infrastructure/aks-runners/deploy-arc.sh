#!/bin/bash

set -e

RESOURCE_GROUP="rg-github-runners"
AKS_CLUSTER="aks-github-runners"
NAMESPACE="github-runners"
GITHUB_APP_PRIVATE_KEY_PATH="./github-app-private-key.pem"

echo "== Deploying Actions Runner Controller to AKS..."

# Get AKS credentials
echo "== Getting AKS credentials..."
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER --overwrite-existing

# Create namespace
echo "== Creating namespace..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Build and push runner image
echo "== Building and pushing runner image..."
ACR_LOGIN_SERVER=$(az acr show --name $(az acr list --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv) --resource-group $RESOURCE_GROUP --query loginServer -o tsv)
ACR_NAME=$(echo $ACR_LOGIN_SERVER | cut -d. -f1)
az acr login --name $ACR_NAME

docker build -t $ACR_LOGIN_SERVER/github-runner:latest ./docker
docker push $ACR_LOGIN_SERVER/github-runner:latest

# Create GitHub App secret
echo "== Creating GitHub App secret..."
kubectl create secret generic github-auth \
        --namespace=$NAMESPACE \
        --from-literal=github_app_id=$GITHUB_APP_ID \
        --from-literal=github_app_installation_id=$GITHUB_APP_INSTALLATION_ID \
        --from-file=github_app_private_key=$GITHUB_APP_PRIVATE_KEY_PATH \
        --dry-run=client -o yaml | kubectl apply -f -

# Add Actions Runner Controller Helm repo
echo "== Adding ARC Helm repository..."
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
helm repo update

# Install cert-manager
echo "== Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

echo "Waiting for cert-manager..."
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager -n cert-manager
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager-webhook -n cert-manager

# Install Actions Runner Controller
echo "== Installing Actions Runner Controller..."
helm upgrade --install arc \
        actions-runner-controller/actions-runner-controller \
        --namespace actions-runner-system \
        --create-namespace \
        --set syncPeriod=1m \
        --set authSecret.create=true \
        --set authSecret.github_app_id=$GITHUB_APP_ID \
        --set authSecret.github_app_installation_id=$GITHUB_APP_INSTALLATION_ID \
        --set-file authSecret.github_app_private_key=$GITHUB_APP_PRIVATE_KEY_PATH \
        --wait

# Deploy runner scale sets
echo "== Deploying runner scale sets..."

for BU in finance marketing engineering; do
        echo "Creating runner deployment for $BU..."

        kubectl apply -f - <<EOF
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
    name: ${BU}-runners
    namespace: $NAMESPACE
spec:
    replicas: 1
    template:
        spec:
            organization: $GITHUB_ORG
            group: $BU
            labels:
                - self-hosted
                - linux
                - $BU
                - infrastructure
            image: $ACR_LOGIN_SERVER/github-runner:latest
            dockerdWithinRunnerContainer: true
            resources:
                requests:
                    cpu: "2"
                    memory: "4Gi"
                limits:
                    cpu: "4"
                    memory: "8Gi"
            tolerations:
                - key: business-unit
                  operator: Equal
                  value: $BU
                  effect: NoSchedule
            nodeSelector:
                business-unit: $BU
---
apiVersion: actions.summerwind.dev/v1alpha1
kind: HorizontalRunnerAutoscaler
metadata:
    name: ${BU}-runners-autoscaler
    namespace: $NAMESPACE
spec:
    scaleTargetRef:
        name: ${BU}-runners
    minReplicas: 1
    maxReplicas: 20
    metrics:
        - type: PercentageRunnersBusy
          scaleUpThreshold: '0.75'
          scaleDownThreshold: '0.25'
          scaleUpFactor: '2'
          scaleDownFactor: '0.5'
EOF
done

echo "ARC deployment complete!"
echo "== Check runner status:"
echo "    kubectl get runners -n $NAMESPACE"
echo "    kubectl get horizontalrunnerautoscaler -n $NAMESPACE"
