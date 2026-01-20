#!/bin/bash
# Sync the workflow template with the current MODULE_DEFINITIONS from the MCP server
#
# Usage:
#   ./scripts/sync-workflow-template.sh [MCP_SERVER_URL]
#
# If MCP_SERVER_URL is not provided, defaults to the production server

set -e

MCP_SERVER_URL="${1:-https://ca-mcp-prod.mangoflower-3bcf53fc.centralus.azurecontainerapps.io}"
TEMPLATE_FILE="templates/infrastructure-workflow.yaml"

echo "Fetching module schema from MCP server..."
SCHEMA=$(curl -s "${MCP_SERVER_URL}/schema/modules")

if [ -z "$SCHEMA" ] || [ "$SCHEMA" == "null" ]; then
    echo "Error: Could not fetch schema from ${MCP_SERVER_URL}/schema/modules"
    exit 1
fi

# Extract valid_types as a Python list string
VALID_TYPES=$(echo "$SCHEMA" | jq -r '.valid_types | @json')

if [ -z "$VALID_TYPES" ] || [ "$VALID_TYPES" == "null" ]; then
    echo "Error: Could not extract valid_types from schema"
    exit 1
fi

echo "Valid types from MCP server: $VALID_TYPES"

# Check if template file exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file not found: $TEMPLATE_FILE"
    exit 1
fi

# Get current valid_types from template
CURRENT_TYPES=$(grep -o "valid_types = \[.*\]" "$TEMPLATE_FILE" | head -1)
echo "Current types in template: $CURRENT_TYPES"

# Update the template file with new valid_types
# The format in the template is: valid_types = ['type1', 'type2', ...]
NEW_TYPES_LINE="valid_types = $VALID_TYPES"

# Use sed to replace the line
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS sed
    sed -i '' "s/valid_types = \[.*\]/${NEW_TYPES_LINE}/" "$TEMPLATE_FILE"
else
    # Linux sed
    sed -i "s/valid_types = \[.*\]/${NEW_TYPES_LINE}/" "$TEMPLATE_FILE"
fi

echo "Updated template with: $NEW_TYPES_LINE"

# Verify the change
UPDATED_TYPES=$(grep -o "valid_types = \[.*\]" "$TEMPLATE_FILE" | head -1)
echo "Verified update: $UPDATED_TYPES"

# Check if there are changes
if git diff --quiet "$TEMPLATE_FILE" 2>/dev/null; then
    echo "No changes needed - template is already in sync"
else
    echo "Template updated successfully!"
    echo ""
    echo "Changes:"
    git diff "$TEMPLATE_FILE" 2>/dev/null || diff <(echo "$CURRENT_TYPES") <(echo "$UPDATED_TYPES")
fi
