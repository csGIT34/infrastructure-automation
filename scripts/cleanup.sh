#!/bin/bash

set -e

echo "=========================================="
echo "Infrastructure Platform Cleanup Script"
echo "=========================================="
echo ""
echo "WARNING: This will destroy all platform resources!"
echo ""

read -p "Are you sure you want to continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

# Destroy Monitoring
echo ""
echo "Destroying Monitoring..."
cd infrastructure/monitoring/infrastructure
terraform destroy -auto-approve || true

# Destroy API Gateway
echo ""
echo "Destroying API Gateway..."
cd ../../api-gateway/infrastructure
terraform destroy -auto-approve || true

# Destroy AKS Runners
echo ""
echo "Destroying AKS Runners..."
cd ../../aks-runners
terraform destroy -auto-approve || true

# Destroy State Storage (last, as it holds state)
echo ""
echo "Destroying State Storage..."
cd ../../terraform/state-storage
terraform destroy -auto-approve || true

echo ""
echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="
