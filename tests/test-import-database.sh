#!/bin/bash
# Unit tests for import-database.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=lib/colors.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/colors.sh"

echo -e "${BLUE}Testing import-database.sh...${NC}"

# Test 1: Script is executable
test_script_executable() {
    if [ -x "$SCRIPT_DIR/scripts/import-database.sh" ]; then
        echo -e "${GREEN}✓ import-database.sh is executable${NC}"
    else
        echo -e "${RED}✗ import-database.sh is not executable${NC}"
        exit 1
    fi
}

# Test 2: Script has error handling
test_error_handling() {
    if grep -q "set -e" "$SCRIPT_DIR/scripts/import-database.sh"; then
        echo -e "${GREEN}✓ Script has error handling (set -e)${NC}"
    else
        echo -e "${YELLOW}⊘ Script missing 'set -e'${NC}"
    fi
}

# Test 3: Script validates required variables
test_variable_validation() {
    if grep -q "S3_BUCKET\|S3_DATABASE_PATH" "$SCRIPT_DIR/scripts/import-database.sh"; then
        echo -e "${GREEN}✓ Script checks required S3 variables${NC}"
    else
        echo -e "${RED}✗ Script doesn't validate S3 variables${NC}"
        exit 1
    fi
}

# Test 4: Script handles gzip decompression
test_gzip_handling() {
    if grep -q "\.gz\|gunzip\|zcat" "$SCRIPT_DIR/scripts/import-database.sh"; then
        echo -e "${GREEN}✓ Script handles .gz decompression${NC}"
    else
        echo -e "${YELLOW}⊘ Script may not handle compressed dumps${NC}"
    fi
}

# Test 5: Script has retry logic for MySQL
test_retry_logic() {
    if grep -q "retry\|attempt\|for.*in" "$SCRIPT_DIR/scripts/import-database.sh"; then
        echo -e "${GREEN}✓ Script has retry/retry logic for MySQL connection${NC}"
    else
        echo -e "${YELLOW}⊘ Script may not have retry logic${NC}"
    fi
}

# Test 6: Script skips import if database exists
test_skip_if_exists() {
    if grep -q "SHOW TABLES\|table_count\|skip\|already" "$SCRIPT_DIR/scripts/import-database.sh"; then
        echo -e "${GREEN}✓ Script checks if database already exists${NC}"
    else
        echo -e "${YELLOW}⊘ Script may not skip existing databases${NC}"
    fi
}

# Test 7: Script passes DB_PORT to mysql commands
test_mysql_port_usage() {
    local file="$SCRIPT_DIR/scripts/import-database.sh"
    local mysql_total
    local mysql_with_port
    local default_assignment_count

    default_assignment_count=$(grep -Ec 'DB_PORT="\$\{DB_PORT:-3306\}"' "$file")
    if [ "$default_assignment_count" -ne 1 ]; then
        echo -e "${RED}✗ Script should assign DB_PORT default exactly once (found $default_assignment_count)${NC}"
        exit 1
    fi

    mysql_total=$(grep -Ec '^[[:space:]]*(if[[:space:]]+)?(mysql[[:space:]]|.*\|[[:space:]]*mysql[[:space:]])' "$file")
    mysql_with_port=$(grep -Ec '^[[:space:]]*(if[[:space:]]+)?(mysql[[:space:]]|.*\|[[:space:]]*mysql[[:space:]]).*-P "\$DB_PORT"' "$file")

    if [ "$mysql_total" -eq 0 ]; then
        echo -e "${RED}✗ Script does not contain mysql commands to validate${NC}"
        exit 1
    fi

    if [ "$mysql_with_port" -eq "$mysql_total" ]; then
        echo -e "${GREEN}✓ DB_PORT default is set once and all mysql commands use -P \"\$DB_PORT\"${NC}"
    else
        echo -e "${RED}✗ Not all mysql commands use -P \"\$DB_PORT\" (found $mysql_with_port/$mysql_total)${NC}"
        exit 1
    fi
}

# Run tests
test_script_executable
test_error_handling
test_variable_validation
test_gzip_handling
test_retry_logic
test_skip_if_exists
test_mysql_port_usage

echo -e "${GREEN}✓ Import database tests passed${NC}"
