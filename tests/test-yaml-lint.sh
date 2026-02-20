#!/bin/bash
# Tests for YAML file linting
#
# This test ensures all YAML files in the repository follow consistent
# formatting and syntax rules using yamllint.
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Testing YAML files...${NC}"

# Test 1: yamllint is available
test_yamllint_available() {
    if command -v yamllint &> /dev/null; then
        echo -e "${GREEN}✓ yamllint is available${NC}"
    else
        echo -e "${RED}✗ yamllint not found - install with: pip install yamllint${NC}"
        exit 1
    fi
}

# Test 2: yamllint config exists
test_yamllint_config_exists() {
    if [ -f "$SCRIPT_DIR/.yamllint" ]; then
        echo -e "${GREEN}✓ .yamllint config exists${NC}"
    else
        echo -e "${RED}✗ .yamllint config not found${NC}"
        exit 1
    fi
}

# Test 3: Lint all YAML files
test_yaml_files() {
    local yaml_files=$(find "$SCRIPT_DIR" -type f \( -name "*.yml" -o -name "*.yaml" \) \
        ! -path "*/node_modules/*" \
        ! -path "*/.git/*" \
        ! -path "*/vendor/*")
    
    if [ -z "$yaml_files" ]; then
        echo -e "${YELLOW}⊘ No YAML files found${NC}"
        return 0
    fi
    
    local file_count=$(echo "$yaml_files" | wc -l)
    echo -e "${YELLOW}  Linting $file_count YAML file(s)...${NC}"
    
    # Run yamllint and capture output
    if echo "$yaml_files" | xargs yamllint -f parsable 2>&1; then
        echo -e "${GREEN}✓ All YAML files passed linting${NC}"
    else
        echo -e "${RED}✗ YAML linting failed${NC}"
        echo ""
        echo "To fix linting errors, run:"
        echo "  yamllint <file>"
        echo ""
        echo "Common fixes:"
        echo "  - Remove trailing whitespace"
        echo "  - Fix indentation (use 2 spaces)"
        echo "  - Ensure line length < 120 characters"
        exit 1
    fi
}

# Run tests
test_yamllint_available
test_yamllint_config_exists
test_yaml_files

echo -e "${GREEN}✓ YAML lint tests passed${NC}"
