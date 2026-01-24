#!/bin/bash
# Manual test runner - allows inspection before teardown
#
# Usage:
#   ./manual-test.sh patterns/keyvault    # Apply and wait for inspection
#   ./manual-test.sh patterns/keyvault destroy  # Destroy after inspection

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check for .env
if [[ ! -f "setup/.env" ]]; then
    echo -e "${RED}Error: setup/.env not found${NC}"
    echo "Copy setup/env.example to setup/.env and fill in your credentials"
    exit 1
fi

source setup/.env

# Verify required env vars
if [[ -z "$ARM_CLIENT_ID" || -z "$ARM_CLIENT_SECRET" || -z "$ARM_TENANT_ID" || -z "$ARM_SUBSCRIPTION_ID" ]]; then
    echo -e "${RED}Error: Missing ARM_* environment variables${NC}"
    exit 1
fi

# Check for owner email (used by pattern tests)
if [[ -z "$TF_VAR_owner_email" ]]; then
    echo -e "${YELLOW}TF_VAR_owner_email not set. Add it to setup/.env${NC}"
    read -p "Enter owner email for this test: " TF_VAR_owner_email
    export TF_VAR_owner_email
fi

TEST_PATH="${1:-}"
ACTION="${2:-apply}"

if [[ -z "$TEST_PATH" ]]; then
    echo "Usage: $0 <test-path> [apply|destroy]"
    echo ""
    echo "Examples:"
    echo "  $0 patterns/keyvault          # Apply pattern test"
    echo "  $0 patterns/keyvault destroy  # Destroy after inspection"
    echo "  $0 modules/keyvault           # Apply module test"
    echo ""
    echo "Available tests:"
    echo "  Patterns:"
    for d in patterns/*/; do
        [[ -d "$d" ]] && echo "    - ${d%/}"
    done
    echo "  Modules:"
    for d in modules/*/; do
        [[ -d "$d" ]] && echo "    - ${d%/}"
    done
    exit 1
fi

# Determine the test fixture directory
if [[ "$TEST_PATH" == patterns/* ]]; then
    PATTERN_NAME=$(basename "$TEST_PATH")
    FIXTURE_DIR="$TEST_PATH/${PATTERN_NAME}_pattern_test"
else
    MODULE_NAME=$(basename "$TEST_PATH")
    # Convert module name to fixture format (e.g., keyvault -> keyvault_test)
    FIXTURE_DIR="$TEST_PATH/${MODULE_NAME//-/_}_test"
fi

if [[ ! -d "$FIXTURE_DIR" ]]; then
    echo -e "${RED}Error: Test fixture not found at $FIXTURE_DIR${NC}"
    exit 1
fi

# Generate a unique suffix if not already set
SUFFIX_FILE="$FIXTURE_DIR/.test-suffix"
if [[ "$ACTION" == "apply" ]]; then
    SUFFIX="$(date +%s | tail -c 5)"
    echo "$SUFFIX" > "$SUFFIX_FILE"
elif [[ -f "$SUFFIX_FILE" ]]; then
    SUFFIX=$(cat "$SUFFIX_FILE")
else
    echo -e "${RED}Error: No existing test found. Run 'apply' first.${NC}"
    exit 1
fi

echo -e "${GREEN}Test: $TEST_PATH${NC}"
echo -e "${GREEN}Fixture: $FIXTURE_DIR${NC}"
echo -e "${GREEN}Suffix: $SUFFIX${NC}"
echo ""

cd "$FIXTURE_DIR"

if [[ "$ACTION" == "apply" ]]; then
    echo -e "${YELLOW}Initializing...${NC}"
    terraform init -upgrade

    echo ""
    echo -e "${YELLOW}Planning...${NC}"
    terraform plan -var="resource_suffix=$SUFFIX" -out=tfplan

    echo ""
    echo -e "${YELLOW}Applying...${NC}"
    terraform apply tfplan

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Resources created successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Outputs:"
    terraform output
    echo ""
    echo -e "${YELLOW}Inspect resources in Azure Portal, then run:${NC}"
    echo -e "  ${GREEN}$0 $TEST_PATH destroy${NC}"
    echo ""

elif [[ "$ACTION" == "destroy" ]]; then
    echo -e "${YELLOW}Initializing...${NC}"
    terraform init -upgrade

    echo -e "${YELLOW}Destroying resources...${NC}"
    terraform destroy -var="resource_suffix=$SUFFIX" -auto-approve

    # Purge soft-deleted Key Vaults (runs async, don't wait)
    echo -e "${YELLOW}Purging soft-deleted Key Vaults...${NC}"
    for vault in $(az keyvault list-deleted --query "[?contains(name,'tftest-$SUFFIX')].name" -o tsv 2>/dev/null); do
        location=$(az keyvault list-deleted --query "[?name=='$vault'].properties.location" -o tsv 2>/dev/null)
        echo "  Purging $vault..."
        az keyvault purge --name "$vault" --location "$location" --no-wait 2>/dev/null || true
    done

    # Delete access reviews
    echo -e "${YELLOW}Deleting access reviews...${NC}"
    for id in $(az rest --method GET --url "https://graph.microsoft.com/v1.0/identityGovernance/accessReviews/definitions" --query "value[?contains(displayName,'tftest-$SUFFIX')].id" -o tsv 2>/dev/null); do
        echo "  Deleting review $id..."
        az rest --method DELETE --url "https://graph.microsoft.com/v1.0/identityGovernance/accessReviews/definitions/$id" 2>/dev/null || true
    done

    # Delete security groups
    echo -e "${YELLOW}Deleting security groups...${NC}"
    for gid in $(az ad group list --query "[?contains(displayName,'tftest-$SUFFIX')].id" -o tsv 2>/dev/null); do
        echo "  Deleting group $gid..."
        az ad group delete --group "$gid" 2>/dev/null || true
    done

    # Clean up local files
    rm -f "$SUFFIX_FILE" tfplan
    rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup

    echo ""
    echo -e "${GREEN}Cleanup complete!${NC}"
else
    echo -e "${RED}Unknown action: $ACTION${NC}"
    echo "Use 'apply' or 'destroy'"
    exit 1
fi
