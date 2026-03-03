#!/bin/bash
# Tests for shell script linting with shellcheck
#
# This test ensures all shell scripts in the repository pass shellcheck
# with no warnings or errors.
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/colors.sh
source "$TEST_DIR/lib/colors.sh"

echo -e "${BLUE}Testing shell scripts with shellcheck...${NC}"

# Test 1: shellcheck is available
test_shellcheck_available() {
    if command -v shellcheck &> /dev/null; then
        local version
        version=$(shellcheck --version | awk '/^version:/{print $2}')
        echo -e "${GREEN}✓ shellcheck is available (version $version)${NC}"
    else
        echo -e "${RED}✗ shellcheck not found - install from https://www.shellcheck.net${NC}"
        exit 1
    fi
}

# Test 2: All shell scripts pass shellcheck
test_shell_scripts() {
    local shell_files
    shell_files=$(find "$SCRIPT_DIR" -type f -name "*.sh" \
        ! -path "*/.git/*" \
        ! -path "*/tests/fixtures/*" \
        ! -path "*/vendor/*")

    if [ -z "$shell_files" ]; then
        echo -e "${YELLOW}⊘ No shell scripts found${NC}"
        return 0
    fi

    local file_count
    file_count=$(echo "$shell_files" | wc -l | xargs)
    echo -e "${BLUE}  Linting $file_count shell script(s)...${NC}"

    local output
    if output=$(echo "$shell_files" | xargs shellcheck -x --source-path=SCRIPTDIR --severity=warning 2>&1); then
        echo -e "${GREEN}✓ All shell scripts passed shellcheck${NC}"
    else
        echo -e "${RED}✗ shellcheck found issues:${NC}"
        echo "$output"
        echo ""
        echo "Fix the issues above, or add a '# shellcheck disable=SCxxxx' directive"
        echo "if the warning is a known false positive."
        exit 1
    fi
}

# Run tests
test_shellcheck_available
test_shell_scripts

echo -e "${GREEN}✓ shellcheck tests passed${NC}"
