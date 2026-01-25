#!/bin/bash
# Deploy Dry Run API Azure Function
#
# This script packages the function code with pattern configuration
# and deploys to Azure.
#
# Prerequisites:
# - Azure CLI logged in
# - Azure Functions Core Tools (func) installed
# - Terraform outputs available (function app name)
#
# Usage:
#   ./deploy.sh <function_app_name>
#   ./deploy.sh func-infra-api-dryrun-prod

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
FUNCTIONS_DIR="${SCRIPT_DIR}"
STAGING_DIR="${SCRIPT_DIR}/.deploy-staging"

FUNC_APP_NAME="${1:-}"

if [ -z "$FUNC_APP_NAME" ]; then
    echo "Usage: $0 <function_app_name>"
    echo ""
    echo "To get the function app name from Terraform:"
    echo "  cd terraform/platform/api && terraform output -raw function_app.name"
    exit 1
fi

echo "==> Preparing deployment package..."

# Clean staging directory
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Copy function code
cp -r "${FUNCTIONS_DIR}/dry-run" "${STAGING_DIR}/"
cp "${FUNCTIONS_DIR}/requirements.txt" "${STAGING_DIR}/"
cp "${FUNCTIONS_DIR}/host.json" "${STAGING_DIR}/"
cp "${FUNCTIONS_DIR}/.funcignore" "${STAGING_DIR}/" 2>/dev/null || true

# Copy pattern configuration (single source of truth)
echo "==> Copying pattern configuration..."
mkdir -p "${STAGING_DIR}/config"
cp -r "${REPO_ROOT}/config/patterns" "${STAGING_DIR}/config/"
cp "${REPO_ROOT}/config/sizing-defaults.yaml" "${STAGING_DIR}/config/"

echo "Patterns included:"
ls -la "${STAGING_DIR}/config/patterns/"

# Deploy to Azure
echo "==> Deploying to Azure Function App: $FUNC_APP_NAME..."
cd "$STAGING_DIR"
func azure functionapp publish "$FUNC_APP_NAME" --python

echo "==> Cleaning up..."
rm -rf "$STAGING_DIR"

echo "==> Deployment complete!"
echo ""
echo "API Endpoint: https://${FUNC_APP_NAME}.azurewebsites.net/api/dry-run"
echo ""
echo "Test with:"
echo "  curl -X POST 'https://${FUNC_APP_NAME}.azurewebsites.net/api/dry-run?code=<function_key>' \\"
echo "    -H 'Content-Type: text/yaml' \\"
echo "    -d @examples/keyvault-pattern.yaml"
