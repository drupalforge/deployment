#!/bin/bash
# Unit tests for config/settings.devpanel.php
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS_FILE="$SCRIPT_DIR/config/settings.devpanel.php"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Testing settings.devpanel.php...${NC}"

# Test 1: File exists and syntax is valid
test_file_and_syntax() {
    if [ ! -f "$SETTINGS_FILE" ]; then
        echo -e "${RED}✗ settings.devpanel.php not found${NC}"
        exit 1
    fi

    if php -l "$SETTINGS_FILE" 2>&1 | grep -q "No syntax errors"; then
        echo -e "${GREEN}✓ settings.devpanel.php exists and has valid PHP syntax${NC}"
    else
        echo -e "${RED}✗ PHP syntax errors found in settings.devpanel.php${NC}"
        php -l "$SETTINGS_FILE"
        exit 1
    fi
}

# Test 2: Hash salt is deterministic from database settings
test_hash_salt_deterministic() {
    local salt_a salt_b

    salt_a=$(SETTINGS_FILE="$SETTINGS_FILE" php -r '
putenv("DB_NAME=drupaldb");
putenv("DB_USER=drupal");
putenv("DB_PASSWORD=drupal_password");
putenv("DB_HOST=mysql");
putenv("DB_PORT=3306");
putenv("DB_DRIVER=mysql");
$databases = [];
$settings = [];
include getenv("SETTINGS_FILE");
echo $settings["hash_salt"] ?? "";
')

    salt_b=$(SETTINGS_FILE="$SETTINGS_FILE" php -r '
putenv("DB_NAME=drupaldb");
putenv("DB_USER=drupal");
putenv("DB_PASSWORD=drupal_password");
putenv("DB_HOST=mysql");
putenv("DB_PORT=3306");
putenv("DB_DRIVER=mysql");
$databases = [];
$settings = [];
include getenv("SETTINGS_FILE");
echo $settings["hash_salt"] ?? "";
')

    if [ -z "$salt_a" ]; then
        echo -e "${RED}✗ Hash salt was not set${NC}"
        exit 1
    fi

    if [ "$salt_a" = "$salt_b" ]; then
        echo -e "${GREEN}✓ Hash salt is deterministic for identical database settings${NC}"
    else
        echo -e "${RED}✗ Hash salt is not deterministic for identical database settings${NC}"
        exit 1
    fi
}

# Test 3: Hash salt changes when database settings change
test_hash_salt_changes_with_database() {
    local salt_a salt_b

    salt_a=$(SETTINGS_FILE="$SETTINGS_FILE" php -r '
putenv("DB_NAME=drupaldb");
putenv("DB_USER=drupal");
putenv("DB_PASSWORD=drupal_password");
putenv("DB_HOST=mysql");
putenv("DB_PORT=3306");
putenv("DB_DRIVER=mysql");
$databases = [];
$settings = [];
include getenv("SETTINGS_FILE");
echo $settings["hash_salt"] ?? "";
')

    salt_b=$(SETTINGS_FILE="$SETTINGS_FILE" php -r '
putenv("DB_NAME=drupaldb_alt");
putenv("DB_USER=drupal");
putenv("DB_PASSWORD=drupal_password");
putenv("DB_HOST=mysql");
putenv("DB_PORT=3306");
putenv("DB_DRIVER=mysql");
$databases = [];
$settings = [];
include getenv("SETTINGS_FILE");
echo $settings["hash_salt"] ?? "";
')

    if [ "$salt_a" != "$salt_b" ]; then
        echo -e "${GREEN}✓ Hash salt changes when database settings change${NC}"
    else
        echo -e "${RED}✗ Hash salt did not change when database settings changed${NC}"
        exit 1
    fi
}

# Test 4: Empty hash_salt is replaced (Drupal default is empty string)
test_empty_hash_salt_replaced() {
    local salt

    salt=$(SETTINGS_FILE="$SETTINGS_FILE" php -r '
putenv("DB_NAME=drupaldb");
putenv("DB_USER=drupal");
putenv("DB_PASSWORD=drupal_password");
putenv("DB_HOST=mysql");
putenv("DB_PORT=3306");
putenv("DB_DRIVER=mysql");
$databases = [];
$settings = ["hash_salt" => ""];
include getenv("SETTINGS_FILE");
echo $settings["hash_salt"] ?? "";
')

    if [ -n "$salt" ]; then
        echo -e "${GREEN}✓ Empty hash_salt is replaced with deterministic value${NC}"
    else
        echo -e "${RED}✗ Empty hash_salt was not replaced${NC}"
        exit 1
    fi
}

# Test 5: DB driver must come from environment
test_db_driver_env_usage() {
    local driver

    driver=$(SETTINGS_FILE="$SETTINGS_FILE" php -d display_errors=0 -d error_reporting=0 -r '
putenv("DB_NAME=drupaldb");
putenv("DB_USER=drupal");
putenv("DB_PASSWORD=drupal_password");
putenv("DB_HOST=mysql");
putenv("DB_PORT=3306");
putenv("DB_DRIVER=pgsql");
$databases = [];
$settings = [];
include getenv("SETTINGS_FILE");
echo $databases["default"]["default"]["driver"] ?? "";
')
    driver="$(echo "$driver" | tr -d '\r\n[:space:]')"

    if [ "$driver" = "pgsql" ]; then
        echo -e "${GREEN}✓ DB driver is sourced from DB_DRIVER environment variable${NC}"
    else
        echo -e "${RED}✗ DB driver is not sourced from DB_DRIVER${NC}"
        exit 1
    fi
}

# Run tests
test_file_and_syntax
test_hash_salt_deterministic
test_hash_salt_changes_with_database
test_empty_hash_salt_replaced
test_db_driver_env_usage

echo -e "${GREEN}✓ settings.devpanel.php tests passed${NC}"
