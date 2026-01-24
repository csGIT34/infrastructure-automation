#!/bin/bash
#
# Purge soft-deleted Key Vaults from test runs
#
# Usage:
#   ./cleanup-keyvaults.sh              # List soft-deleted test vaults
#   ./cleanup-keyvaults.sh --purge      # Purge all test vaults
#   ./cleanup-keyvaults.sh --purge-all  # Purge ALL soft-deleted vaults (careful!)

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check Azure CLI auth
check_auth() {
    if ! az account show &> /dev/null; then
        echo -e "${RED}Error: Not logged into Azure${NC}"
        echo "Run: az login"
        echo "Or source your .env: source setup/.env"
        exit 1
    fi

    local sub=$(az account show --query name -o tsv)
    echo -e "${GREEN}✓ Logged in to: $sub${NC}"
    echo ""
}

# List soft-deleted vaults
list_vaults() {
    local filter="$1"

    echo -e "${CYAN}Fetching soft-deleted Key Vaults...${NC}"

    if [ -n "$filter" ]; then
        az keyvault list-deleted \
            --query "[?starts_with(name, '$filter')].{Name:name, Location:properties.location, DeletedDate:properties.deletionDate}" \
            -o table
    else
        az keyvault list-deleted \
            --query "[].{Name:name, Location:properties.location, DeletedDate:properties.deletionDate}" \
            -o table
    fi
}

# Purge vaults matching filter
purge_vaults() {
    local filter="$1"
    local vaults

    echo -e "${CYAN}Finding vaults to purge...${NC}"

    if [ -n "$filter" ]; then
        vaults=$(az keyvault list-deleted --query "[?starts_with(name, '$filter')].name" -o tsv)
    else
        vaults=$(az keyvault list-deleted --query "[].name" -o tsv)
    fi

    if [ -z "$vaults" ]; then
        echo -e "${GREEN}No soft-deleted vaults found${NC}"
        return 0
    fi

    echo "Found vaults to purge:"
    echo "$vaults" | while read vault; do
        echo "  - $vault"
    done
    echo ""

    read -p "Purge these vaults? (y/N) " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Cancelled"
        return 0
    fi

    echo ""
    echo "$vaults" | while read vault; do
        if [ -n "$vault" ]; then
            echo -e "${YELLOW}Purging $vault...${NC}"
            # Get location for the vault
            location=$(az keyvault list-deleted --query "[?name=='$vault'].properties.location" -o tsv)
            if az keyvault purge --name "$vault" --location "$location" 2>/dev/null; then
                echo -e "${GREEN}✓ Purged $vault${NC}"
            else
                echo -e "${RED}✗ Failed to purge $vault${NC}"
            fi
        fi
    done

    echo ""
    echo -e "${GREEN}Done${NC}"
}

# Main
main() {
    check_auth

    case "${1:-}" in
        --purge)
            # Purge test vaults only (kv-tftest-* or tftest)
            echo -e "${YELLOW}Purging test Key Vaults (tftest pattern)...${NC}"
            echo ""
            list_vaults "kv-tftest"
            echo ""
            list_vaults "tftest"
            echo ""

            # Get all test vaults
            vaults=$(az keyvault list-deleted --query "[?starts_with(name, 'kv-tftest') || starts_with(name, 'tftest') || contains(name, 'tftest')].name" -o tsv)

            if [ -z "$vaults" ]; then
                echo -e "${GREEN}No test vaults to purge${NC}"
                exit 0
            fi

            echo "Vaults to purge:"
            echo "$vaults" | while read vault; do
                echo "  - $vault"
            done
            echo ""

            read -p "Purge these vaults? (y/N) " confirm
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                echo "Cancelled"
                exit 0
            fi

            echo ""
            for vault in $vaults; do
                if [ -n "$vault" ]; then
                    echo -ne "${YELLOW}Purging $vault...${NC} "
                    location=$(az keyvault list-deleted --query "[?name=='$vault'].properties.location" -o tsv 2>/dev/null)
                    if [ -z "$location" ]; then
                        echo -e "${RED}(can't find location, skipping)${NC}"
                        continue
                    fi
                    # Run purge with timeout and progress indicator
                    if timeout 120 az keyvault purge --name "$vault" --location "$location" 2>/dev/null; then
                        echo -e "${GREEN}done${NC}"
                    else
                        echo -e "${RED}failed or timeout${NC}"
                    fi
                fi
            done
            ;;

        --purge-all)
            echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
            echo -e "${RED}WARNING: This will purge ALL soft-deleted Key Vaults!${NC}"
            echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
            echo ""
            sub=$(az account show --query name -o tsv)
            sub_id=$(az account show --query id -o tsv)
            echo -e "Subscription: ${YELLOW}$sub${NC}"
            echo -e "ID: ${YELLOW}$sub_id${NC}"
            echo ""
            read -p "Type 'PURGE ALL' to confirm: " confirm
            if [ "$confirm" != "PURGE ALL" ]; then
                echo "Cancelled"
                exit 0
            fi
            purge_vaults ""
            ;;

        --help|-h)
            echo "Key Vault Cleanup Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  (none)        List soft-deleted test vaults"
            echo "  --purge       Purge test vaults (tftest pattern)"
            echo "  --purge-all   Purge ALL soft-deleted vaults"
            echo "  -h, --help    Show this help"
            ;;

        *)
            # Default: list test vaults
            echo -e "${CYAN}Soft-deleted test Key Vaults:${NC}"
            echo ""

            # Show vaults matching test patterns
            az keyvault list-deleted \
                --query "[?starts_with(name, 'kv-tftest') || starts_with(name, 'tftest') || contains(name, 'tftest')].{Name:name, Location:properties.location, DeletedDate:properties.deletionDate}" \
                -o table

            echo ""
            echo "Run '$0 --purge' to purge these vaults"
            ;;
    esac
}

main "$@"
