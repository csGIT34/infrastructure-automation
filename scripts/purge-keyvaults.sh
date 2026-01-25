#!/bin/bash
# Purge soft-deleted Key Vaults
# Usage: ./purge-keyvaults.sh [--force]

set -euo pipefail

FORCE=false
if [[ "${1:-}" == "--force" ]]; then
  FORCE=true
fi

echo "Searching for soft-deleted Key Vaults..."
echo

DELETED=$(az keyvault list-deleted --query "[].{name:name, location:properties.location, deletionDate:properties.deletionDate}" -o json 2>/dev/null)

COUNT=$(echo "$DELETED" | jq length)

if [[ "$COUNT" -eq 0 ]]; then
  echo "No soft-deleted Key Vaults found."
  exit 0
fi

echo "Found $COUNT soft-deleted Key Vault(s):"
echo
echo "$DELETED" | jq -r '.[] | "  - \(.name) (\(.location)) - deleted: \(.deletionDate)"'
echo

if [[ "$FORCE" != true ]]; then
  read -p "Purge all $COUNT Key Vault(s)? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

echo
echo "Purging..."

echo "$DELETED" | jq -r '.[] | "\(.name) \(.location)"' | while read -r NAME LOCATION; do
  echo "  Purging $NAME in $LOCATION..."
  az keyvault purge --name "$NAME" --location "$LOCATION" --no-wait 2>/dev/null || echo "    Failed to purge $NAME"
done

echo
echo "Done. Purge requests submitted (--no-wait)."
