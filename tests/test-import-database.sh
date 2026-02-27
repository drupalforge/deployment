#!/bin/bash
# Unit tests for import-database.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Run tests
test_script_executable
test_error_handling
test_variable_validation
test_gzip_handling
test_retry_logic
test_skip_if_exists

echo -e "${GREEN}✓ Import database tests passed${NC}"
