#!/bin/bash
# Unit tests for PHP coding standards (Drupal)
set -e

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${TEST_DIR%/*}"
SETTINGS_FILE="$SCRIPT_DIR/config/settings.devpanel.php"

# shellcheck source=lib/colors.sh
source "$TEST_DIR/lib/colors.sh"

echo -e "${BLUE}Testing PHP coding standards...${NC}"

# Test 1: PHPCS is installed
test_phpcs_available() {
    if command -v phpcs > /dev/null 2>&1; then
        echo -e "${GREEN}✓ phpcs is available ($(phpcs --version | head -n 1))${NC}"
    else
        echo -e "${RED}✗ phpcs is required but not installed${NC}"
        exit 1
    fi
}

# Test 2: Drupal coding standard is available
test_drupal_standard_available() {
    if phpcs -i 2>/dev/null | grep -q "Drupal"; then
        echo -e "${GREEN}✓ Drupal coding standard is available in phpcs${NC}"
    else
        echo -e "${RED}✗ Drupal coding standard is not available in phpcs${NC}"
        exit 1
    fi
}

# Test 3: settings.devpanel.php passes Drupal coding standard checks
test_settings_phpcs() {
    local output
    if output=$(phpcs --standard=Drupal "$SETTINGS_FILE" 2>&1); then
        echo -e "${GREEN}✓ settings.devpanel.php passes Drupal coding standards${NC}"
    else
        echo -e "${RED}✗ settings.devpanel.php failed Drupal coding standards${NC}"
        echo "$output"
        exit 1
    fi
}

# Run tests
test_phpcs_available
test_drupal_standard_available
test_settings_phpcs

echo -e "${GREEN}✓ PHP coding standards tests passed${NC}"
