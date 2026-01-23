#!/bin/bash
# Sync the workflow template with the patterns from terraform/patterns/
#
# Usage:
#   ./scripts/sync-workflow-template.sh
#
# This script uses terraform/patterns/ as the source of truth for valid patterns.

set -e

TEMPLATE_FILE="templates/infrastructure-workflow.yaml"
PATTERNS_DIR="terraform/patterns"

echo "Scanning terraform/patterns/ for valid patterns..."

# Get list of pattern directories (source of truth)
if [ ! -d "$PATTERNS_DIR" ]; then
    echo "Error: Patterns directory not found: $PATTERNS_DIR"
    exit 1
fi

# Find all pattern directories that have a main.tf
PATTERNS=()
for dir in "$PATTERNS_DIR"/*/; do
    if [ -f "${dir}main.tf" ]; then
        pattern_name=$(basename "$dir")
        PATTERNS+=("$pattern_name")
    fi
done

# Sort patterns alphabetically
IFS=$'\n' SORTED_PATTERNS=($(sort <<<"${PATTERNS[*]}")); unset IFS

# Build the Python list string for valid_patterns
VALID_PATTERNS="["
first=true
for pattern in "${SORTED_PATTERNS[@]}"; do
    if [ "$first" = true ]; then
        first=false
    else
        VALID_PATTERNS+=", "
    fi
    VALID_PATTERNS+="'$pattern'"
done
VALID_PATTERNS+="]"

echo "Found patterns: $VALID_PATTERNS"

# Check if template file exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file not found: $TEMPLATE_FILE"
    exit 1
fi

# Get current valid_patterns from template
CURRENT_PATTERNS=$(grep -o "valid_patterns = \[.*\]" "$TEMPLATE_FILE" | head -1 || echo "not found")
echo "Current patterns in template: $CURRENT_PATTERNS"

# Update the template file with new valid_patterns
NEW_PATTERNS_LINE="valid_patterns = $VALID_PATTERNS"

# Use sed to replace the line
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS sed
    sed -i '' "s/valid_patterns = \[.*\]/${NEW_PATTERNS_LINE}/" "$TEMPLATE_FILE"
else
    # Linux sed
    sed -i "s/valid_patterns = \[.*\]/${NEW_PATTERNS_LINE}/" "$TEMPLATE_FILE"
fi

echo "Updated template with: $NEW_PATTERNS_LINE"

# Verify the change
UPDATED_PATTERNS=$(grep -o "valid_patterns = \[.*\]" "$TEMPLATE_FILE" | head -1)
echo "Verified update: $UPDATED_PATTERNS"

# Check if there are changes
if git diff --quiet "$TEMPLATE_FILE" 2>/dev/null; then
    echo "No changes needed - template is already in sync"
else
    echo "Template updated successfully!"
    echo ""
    echo "Changes:"
    git diff "$TEMPLATE_FILE" 2>/dev/null || diff <(echo "$CURRENT_PATTERNS") <(echo "$UPDATED_PATTERNS")
fi
