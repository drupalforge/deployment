#!/bin/bash
# Docker build tests with automatic cleanup
# Tests that Docker images build successfully for all supported PHP versions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test configuration
PHP_VERSIONS=("8.2" "8.3")
TEST_TAG_PREFIX="drupalforge-deployment-test"
BUILD_FAILED=0

echo -e "${BLUE}Testing Docker builds...${NC}"
echo ""

# Function to cleanup test images
cleanup_images() {
    echo -e "${YELLOW}Cleaning up test images...${NC}"
    for version in "${PHP_VERSIONS[@]}"; do
        local tag="${TEST_TAG_PREFIX}:${version}"
        if docker images -q "$tag" 2>/dev/null | grep -q .; then
            echo "  Removing image: $tag"
            docker rmi "$tag" 2>/dev/null || true
        fi
    done
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

# Ensure cleanup on exit
trap cleanup_images EXIT

# Test builds for each PHP version
for version in "${PHP_VERSIONS[@]}"; do
    tag="${TEST_TAG_PREFIX}:${version}"
    
    echo -e "${YELLOW}Building PHP ${version} image...${NC}"
    
    if docker build \
        --build-arg PHP_VERSION="$version" \
        -t "$tag" \
        -f "$PROJECT_ROOT/Dockerfile" \
        "$PROJECT_ROOT" 2>&1 | grep -E "(ERROR|Successfully|DONE)" | tail -5; then
        
        echo -e "${GREEN}✓ PHP ${version} build successful${NC}"
        
        # Verify the user is set correctly
        echo -e "${YELLOW}  Verifying user configuration...${NC}"
        user_check=$(docker run --rm --entrypoint sh "$tag" -c 'whoami' 2>/dev/null)
        if [ "$user_check" == "www" ]; then
            echo -e "${GREEN}  ✓ User is 'www' (correct)${NC}"
        else
            echo -e "${RED}  ✗ User is '$user_check' (expected 'www')${NC}"
            BUILD_FAILED=1
        fi
        
        # Verify scripts are executable
        echo -e "${YELLOW}  Verifying script permissions...${NC}"
        script_check=$(docker run --rm --entrypoint sh "$tag" -c 'ls -la /usr/local/bin/deployment-entrypoint | grep "^-rwx"' 2>/dev/null)
        if [ -n "$script_check" ]; then
            echo -e "${GREEN}  ✓ Scripts have execute permissions${NC}"
        else
            echo -e "${RED}  ✗ Scripts missing execute permissions${NC}"
            BUILD_FAILED=1
        fi
        
    else
        echo -e "${RED}✗ PHP ${version} build failed${NC}"
        BUILD_FAILED=1
    fi
    echo ""
done

if [ $BUILD_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All Docker builds passed${NC}"
    exit 0
else
    echo -e "${RED}✗ Some Docker builds failed${NC}"
    exit 1
fi
