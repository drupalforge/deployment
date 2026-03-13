#!/bin/bash
# Unit tests for config/settings.devpanel.php
# shellcheck disable=SC2016  # Single quotes are intentional throughout: PHP code passed to php -r
set -e

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${TEST_DIR%/*}"
SETTINGS_FILE="$SCRIPT_DIR/config/settings.devpanel.php"

# shellcheck source=lib/colors.sh
source "$TEST_DIR/lib/colors.sh"

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

# Test 6: Existing config sync directory setting is preserved
test_config_sync_directory_preserved_when_preconfigured() {
    local temp_dir sync_dir configured

    temp_dir=$(mktemp -d)
    sync_dir="$temp_dir/custom/sync"
    trap 'rm -rf "$temp_dir"' RETURN

    configured=$(SETTINGS_FILE="$SETTINGS_FILE" SYNC_DIR="$sync_dir" php -r '
putenv("DB_NAME=drupaldb");
putenv("DB_USER=drupal");
putenv("DB_PASSWORD=drupal_password");
putenv("DB_HOST=mysql");
putenv("DB_PORT=3306");
putenv("DB_DRIVER=mysql");
$databases = [];
$settings = ["config_sync_directory" => getenv("SYNC_DIR")];
$app_root = "/var/www/html/web";
include getenv("SETTINGS_FILE");
echo $settings["config_sync_directory"] ?? "";
')

    if [ "$configured" = "$sync_dir" ]; then
        echo -e "${GREEN}✓ Existing config sync directory setting is preserved${NC}"
    else
        echo -e "${RED}✗ Existing config sync directory setting was overridden${NC}"
        exit 1
    fi
}

# Test 7: MySQL driver defaults PDO ssl verify server cert to OFF
test_mysql_ssl_verify_default() {
        local result

        result=$(SETTINGS_FILE="$SETTINGS_FILE" php -r '
putenv("DB_NAME=drupaldb");
putenv("DB_USER=drupal");
putenv("DB_PASSWORD=drupal_password");
putenv("DB_HOST=mysql");
putenv("DB_PORT=3306");
putenv("DB_DRIVER=mysql");
$databases = [];
$settings = [];
$app_root = "/var/www/html/web";
include getenv("SETTINGS_FILE");

$attr = null;
if (defined("Pdo\\Mysql::ATTR_SSL_VERIFY_SERVER_CERT")) {
    $attr = constant("Pdo\\Mysql::ATTR_SSL_VERIFY_SERVER_CERT");
} elseif (defined("PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT")) {
    $attr = constant("PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT");
}

if ($attr === null) {
    echo "unsupported";
    exit(0);
}

$pdo = $databases["default"]["default"]["pdo"] ?? [];
echo (array_key_exists($attr, $pdo) ? "present:" : "missing:");
$value = $pdo[$attr] ?? null;
if ($value === "OFF") {
    echo "OFF";
} elseif ($value === "off") {
    echo "off";
} elseif ($value === false) {
    echo "false";
} elseif ($value === true) {
    echo "true";
} elseif ($value === null) {
    echo "null";
} else {
    echo (string) $value;
}
')

        if [ "$result" = "unsupported" ]; then
                echo -e "${YELLOW}⊘ Skipped: MySQL PDO ssl verify constant is unavailable in this PHP runtime${NC}"
                return 0
        fi

        if [ "$result" = "present:OFF" ] || [ "$result" = "present:off" ]; then
            echo -e "${GREEN}✓ MySQL driver defaults PDO ssl verify server cert to OFF${NC}"
        else
            echo -e "${RED}✗ MySQL driver did not default PDO ssl verify server cert to OFF${NC}"
                exit 1
        fi
}

# Test 8: Non-MySQL drivers do not receive MySQL PDO ssl verify setting
test_non_mysql_does_not_set_mysql_ssl_verify() {
        local result

        result=$(SETTINGS_FILE="$SETTINGS_FILE" php -r '
putenv("DB_NAME=drupaldb");
putenv("DB_USER=drupal");
putenv("DB_PASSWORD=drupal_password");
putenv("DB_HOST=mysql");
putenv("DB_PORT=3306");
putenv("DB_DRIVER=pgsql");
$databases = [];
$settings = [];
$app_root = "/var/www/html/web";
include getenv("SETTINGS_FILE");

$attr = null;
if (defined("Pdo\\Mysql::ATTR_SSL_VERIFY_SERVER_CERT")) {
    $attr = constant("Pdo\\Mysql::ATTR_SSL_VERIFY_SERVER_CERT");
} elseif (defined("PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT")) {
    $attr = constant("PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT");
}

if ($attr === null) {
    echo "unsupported";
    exit(0);
}

$pdo = $databases["default"]["default"]["pdo"] ?? [];
echo (array_key_exists($attr, $pdo) ? "present" : "missing");
')

        if [ "$result" = "unsupported" ]; then
                echo -e "${YELLOW}⊘ Skipped: MySQL PDO ssl verify constant is unavailable in this PHP runtime${NC}"
                return 0
        fi

        if [ "$result" = "missing" ]; then
                echo -e "${GREEN}✓ Non-MySQL drivers do not receive MySQL PDO ssl verify setting${NC}"
        else
                echo -e "${RED}✗ Non-MySQL driver unexpectedly received MySQL PDO ssl verify setting${NC}"
                exit 1
        fi
}

# Test 9: Existing ssl verify value is overridden while unrelated PDO values are preserved
test_existing_pdo_values_overridden() {
        local result

        result=$(SETTINGS_FILE="$SETTINGS_FILE" php -r '
putenv("DB_NAME=drupaldb");
putenv("DB_USER=drupal");
putenv("DB_PASSWORD=drupal_password");
putenv("DB_HOST=mysql");
putenv("DB_PORT=3306");
putenv("DB_DRIVER=mysql");

$attr = null;
if (defined("Pdo\\Mysql::ATTR_SSL_VERIFY_SERVER_CERT")) {
    $attr = constant("Pdo\\Mysql::ATTR_SSL_VERIFY_SERVER_CERT");
} elseif (defined("PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT")) {
    $attr = constant("PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT");
}

if ($attr === null) {
    echo "unsupported";
    exit(0);
}

$databases = [
    "default" => [
        "default" => [
            "driver" => "mysql",
            "pdo" => [
                $attr => true,
                123456 => "keep",
            ],
        ],
    ],
];
$settings = [];
$app_root = "/var/www/html/web";
include getenv("SETTINGS_FILE");

$pdo = $databases["default"]["default"]["pdo"] ?? [];
$attrValue = $pdo[$attr] ?? null;
$customValue = $pdo[123456] ?? null;
echo (($attrValue === "OFF" || $attrValue === "off") ? "attr-overridden" : "attr-not-overridden");
echo ":";
echo (($customValue === "keep") ? "custom-preserved" : "custom-changed");
')

        if [ "$result" = "unsupported" ]; then
                echo -e "${YELLOW}⊘ Skipped: MySQL PDO ssl verify constant is unavailable in this PHP runtime${NC}"
                return 0
        fi

        if [ "$result" = "attr-overridden:custom-preserved" ]; then
            echo -e "${GREEN}✓ Existing ssl verify value is overridden while unrelated PDO values are preserved${NC}"
        else
            echo -e "${RED}✗ Existing ssl verify override behavior is incorrect${NC}"
                exit 1
        fi
}

# Run tests
test_file_and_syntax
test_hash_salt_deterministic
test_hash_salt_changes_with_database
test_empty_hash_salt_replaced
test_db_driver_env_usage
test_config_sync_directory_preserved_when_preconfigured
test_mysql_ssl_verify_default
test_non_mysql_does_not_set_mysql_ssl_verify
test_existing_pdo_values_overridden

echo -e "${GREEN}✓ settings.devpanel.php tests passed${NC}"
