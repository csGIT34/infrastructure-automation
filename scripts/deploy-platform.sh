#!/bin/bash

set -e

echo "=========================================="
echo "Infrastructure Platform Deployment Script"
echo "=========================================="

# Check required environment variables
required_vars=(
    "AZURE_SUBSCRIPTION_ID"
    "AZURE_LOCATION"
    "GITHUB_ORG"
    "GITHUB_REPO"
    "GITHUB_APP_ID"
    "GITHUB_APP_INSTALLATION_ID"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: $var is not set"
        exit 1
    fi
done

echo "Configuration:"
echo "  Subscription: $AZURE_SUBSCRIPTION_ID"
echo "  Location:     $AZURE_LOCATION"
echo "  GitHub Org:   $GITHUB_ORG"

# Login to Azure
echo ""
echo "Step 1: Azure Login"
echo "-------------------"
az login
az account set --subscription $AZURE_SUBSCRIPTION_ID

# Deploy Terraform State Storage
echo ""
echo "Step 2: Deploy Terraform State Storage"
echo "---------------------------------------"
cd terraform/state-storage
terraform init
terraform apply -var="location=$AZURE_LOCATION" -auto-approve

export TF_STATE_STORAGE_ACCOUNT=$(terraform output -raw storage_account_name)
export TF_STATE_RESOURCE_GROUP=$(terraform output -raw resource_group_name)

echo "State Storage Account: $TF_STATE_STORAGE_ACCOUNT"

# Deploy AKS Runners
echo ""
echo "Step 3: Deploy AKS Runners"
echo "--------------------------"
cd ../../infrastructure/aks-runners
terraform init
terraform apply -var="location=$AZURE_LOCATION" -auto-approve

export AKS_CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
export ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server)

echo "AKS Cluster: $AKS_CLUSTER_NAME"
echo "ACR Server:  $ACR_LOGIN_SERVER"

# Deploy Actions Runner Controller
echo ""
echo "Step 4: Deploy Actions Runner Controller"
echo "-----------------------------------------"
bash deploy-arc.sh

# Deploy API Gateway
echo ""
echo "Step 5: Deploy API Gateway"
echo "--------------------------"
cd ../api-gateway/infrastructure
terraform init
terraform apply -var="location=$AZURE_LOCATION" -auto-approve

export API_FUNCTION_URL=$(terraform output -raw function_app_url)
export API_FUNCTION_NAME=$(terraform output -raw function_app_name)
export SERVICEBUS_NAMESPACE=$(terraform output -raw servicebus_namespace)
export COSMOS_ENDPOINT=$(terraform output -raw cosmos_endpoint)

echo "API URL:    $API_FUNCTION_URL"
echo "Service Bus: $SERVICEBUS_NAMESPACE"

# Deploy Function App code
echo ""
echo "Step 6: Deploy Function App Code"
echo "---------------------------------"
cd ..
func azure functionapp publish $API_FUNCTION_NAME

# Deploy Monitoring
echo ""
echo "Step 7: Deploy Monitoring"
echo "-------------------------"
cd ../monitoring/infrastructure
terraform init
terraform apply -var="location=$AZURE_LOCATION" -auto-approve

# Output summary
echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Resources Created:"
echo "  - Terraform State Storage: $TF_STATE_STORAGE_ACCOUNT"
echo "  - AKS Cluster:            $AKS_CLUSTER_NAME"
echo "  - Container Registry:     $ACR_LOGIN_SERVER"
echo "  - API Gateway:            $API_FUNCTION_URL"
echo "  - Service Bus:            $SERVICEBUS_NAMESPACE"
echo "  - Cosmos DB:              $COSMOS_ENDPOINT"
echo ""
echo "Next Steps:"
echo "  1. Configure GitHub Secrets in your repository"
echo "  2. Install the CLI: cd cli && pip install -e ."
echo "  3. Set CLI environment variables:"
echo "     export INFRA_API_URL=$API_FUNCTION_URL"
echo ""
