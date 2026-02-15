#!/bin/bash
# Tests for YAML file linting
#
# This test ensures all YAML files in the repository follow consistent
# formatting and syntax rules using yamllint.
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Testing YAML files..."

# Test 1: yamllint is available
test_yamllint_available() {
    if command -v yamllint &> /dev/null; then
        echo "✓ yamllint is available"
    else
        echo "✗ yamllint not found - install with: pip install yamllint"
        exit 1
    fi
}

# Test 2: yamllint config exists
test_yamllint_config_exists() {
    if [ -f "$SCRIPT_DIR/.yamllint" ]; then
        echo "✓ .yamllint config exists"
    else
        echo "✗ .yamllint config not found"
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
        echo "⊘ No YAML files found"
        return 0
    fi
    
    local file_count=$(echo "$yaml_files" | wc -l)
    echo "  Linting $file_count YAML file(s)..."
    
    # Run yamllint and capture output
    if echo "$yaml_files" | xargs yamllint -f parsable 2>&1; then
        echo "✓ All YAML files passed linting"
    else
        echo "✗ YAML linting failed"
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

echo "✓ YAML lint tests passed"
