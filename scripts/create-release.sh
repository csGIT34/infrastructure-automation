#!/bin/bash
# create-release.sh - Helper script to create pattern releases
#
# Usage:
#   ./scripts/create-release.sh <pattern> <version>
#
# Examples:
#   ./scripts/create-release.sh keyvault 1.2.0
#   ./scripts/create-release.sh postgresql 2.0.0
#
# This script:
# 1. Validates the pattern exists
# 2. Validates the version format
# 3. Checks that you're on the main branch
# 4. Creates and pushes the tag
# 5. The release workflow will automatically create the GitHub release

set -e

PATTERN="$1"
VERSION="$2"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validate arguments
if [ -z "$PATTERN" ] || [ -z "$VERSION" ]; then
    echo -e "${RED}Error: Missing arguments${NC}"
    echo ""
    echo "Usage: $0 <pattern> <version>"
    echo ""
    echo "Examples:"
    echo "  $0 keyvault 1.2.0"
    echo "  $0 postgresql 2.0.0"
    echo ""
    echo "Available patterns:"
    ls -1 terraform/patterns/ 2>/dev/null | grep -v "^$" || echo "  (none found - are you in the repo root?)"
    exit 1
fi

# Validate pattern exists
if [ ! -d "terraform/patterns/$PATTERN" ]; then
    echo -e "${RED}Error: Pattern '$PATTERN' not found${NC}"
    echo ""
    echo "Available patterns:"
    ls -1 terraform/patterns/
    exit 1
fi

# Validate version format
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9]+)?$ ]]; then
    echo -e "${RED}Error: Invalid version format '$VERSION'${NC}"
    echo ""
    echo "Version must be in semver format: X.Y.Z or X.Y.Z-prerelease"
    echo "Examples: 1.0.0, 2.1.0, 1.0.0-beta1"
    exit 1
fi

TAG="${PATTERN}/v${VERSION}"

# Check if tag already exists
if git tag -l "$TAG" | grep -q "$TAG"; then
    echo -e "${RED}Error: Tag '$TAG' already exists${NC}"
    echo ""
    echo "Existing tags for $PATTERN:"
    git tag -l "${PATTERN}/v*" | sort -V
    exit 1
fi

# Check current branch
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo -e "${YELLOW}Warning: You are on branch '$CURRENT_BRANCH', not 'main'${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted"
        exit 1
    fi
fi

# Check for uncommitted changes
if ! git diff --quiet || ! git diff --staged --quiet; then
    echo -e "${YELLOW}Warning: You have uncommitted changes${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted"
        exit 1
    fi
fi

# Get current version
CURRENT_VERSION=""
if [ -f "terraform/patterns/$PATTERN/VERSION" ]; then
    CURRENT_VERSION=$(cat "terraform/patterns/$PATTERN/VERSION")
fi

# Show release info
echo ""
echo -e "${GREEN}Creating release for pattern: $PATTERN${NC}"
echo "  Tag: $TAG"
if [ -n "$CURRENT_VERSION" ]; then
    echo "  Previous version: $CURRENT_VERSION"
fi
echo "  New version: $VERSION"
echo ""

# Show commits since last release
LAST_TAG=$(git tag -l "${PATTERN}/v*" | sort -V | tail -1)
if [ -n "$LAST_TAG" ]; then
    echo "Commits since $LAST_TAG:"
    git log --oneline "$LAST_TAG..HEAD" -- \
        "terraform/patterns/$PATTERN" \
        "terraform/modules" \
        "config/patterns/$PATTERN.yaml" \
        | head -20
    echo ""
fi

# Confirm
read -p "Create and push tag '$TAG'? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted"
    exit 1
fi

# Create tag
echo ""
echo "Creating tag..."
git tag "$TAG"

# Push tag
echo "Pushing tag..."
git push origin "$TAG"

echo ""
echo -e "${GREEN}Success!${NC} Tag '$TAG' created and pushed."
echo ""
echo "The release workflow will now:"
echo "  1. Run tests for the $PATTERN pattern"
echo "  2. Generate changelog from commits"
echo "  3. Create a GitHub release"
echo "  4. Update VERSION and CHANGELOG files"
echo ""
echo "Monitor the release at:"
echo "  https://github.com/$(git remote get-url origin | sed 's/.*github.com[:/]\(.*\)\.git/\1/')/actions"
