#!/bin/bash
# Tests for Markdown file linting
#
# This test validates Markdown formatting and style consistency.
set -e

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${TEST_DIR%/*}"

# shellcheck source=lib/colors.sh
source "$TEST_DIR/lib/colors.sh"

echo -e "${BLUE}Testing Markdown files...${NC}"

# Test 1: markdownlint is available
test_markdownlint_available() {
    if command -v markdownlint >/dev/null 2>&1; then
        local version
        version=$(markdownlint --version 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓ markdownlint is available (version $version)${NC}"
    else
        echo -e "${RED}✗ markdownlint not found - install markdownlint-cli: https://github.com/igorshubovych/markdownlint-cli?tab=readme-ov-file#installation${NC}"
        exit 1
    fi
}

# Test 2: markdownlint config exists
test_markdownlint_config_exists() {
    if [ -f "$SCRIPT_DIR/.markdownlint.json" ]; then
        echo -e "${GREEN}✓ .markdownlint.json config exists${NC}"
    else
        echo -e "${RED}✗ .markdownlint.json config not found${NC}"
        exit 1
    fi
}

# Test 3: Lint all Markdown files
test_markdown_files() {
    local md_files
    md_files=$(find "$SCRIPT_DIR" -type f -name "*.md" \
        ! -path "*/.git/*" \
        ! -path "*/node_modules/*" \
        ! -path "*/vendor/*" \
        ! -path "*/tests/fixtures/*")

    if [ -z "$md_files" ]; then
        echo -e "${YELLOW}⊘ No Markdown files found${NC}"
        return 0
    fi

    local file_count
    file_count=$(echo "$md_files" | wc -l | xargs)
    echo -e "${BLUE}  Linting $file_count Markdown file(s)...${NC}"

    if echo "$md_files" | xargs markdownlint --config "$SCRIPT_DIR/.markdownlint.json"; then
        echo -e "${GREEN}✓ All Markdown files passed linting${NC}"
    else
        echo -e "${RED}✗ Markdown linting failed${NC}"
        echo ""
        echo "To inspect failures, run:"
        echo "  markdownlint --config .markdownlint.json \"**/*.md\""
        echo ""
        exit 1
    fi
}

test_markdownlint_available
test_markdownlint_config_exists
test_markdown_files
echo -e "${GREEN}✓ Markdown lint tests passed${NC}"
