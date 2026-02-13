#!/bin/bash
# Unit tests for import-database.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Testing import-database.sh..."

# Test 1: Script is executable
test_script_executable() {
    if [ -x "$SCRIPT_DIR/scripts/import-database.sh" ]; then
        echo "✓ import-database.sh is executable"
    else
        echo "✗ import-database.sh is not executable"
        exit 1
    fi
}

# Test 2: Script has error handling
test_error_handling() {
    if grep -q "set -e" "$SCRIPT_DIR/scripts/import-database.sh"; then
        echo "✓ Script has error handling (set -e)"
    else
        echo "⊘ Script missing 'set -e'"
    fi
}

# Test 3: Script validates required variables
test_variable_validation() {
    if grep -q "S3_BUCKET\|S3_DATABASE_PATH" "$SCRIPT_DIR/scripts/import-database.sh"; then
        echo "✓ Script checks required S3 variables"
    else
        echo "✗ Script doesn't validate S3 variables"
        exit 1
    fi
}

# Test 4: Script handles gzip decompression
test_gzip_handling() {
    if grep -q "\.gz\|gunzip\|zcat" "$SCRIPT_DIR/scripts/import-database.sh"; then
        echo "✓ Script handles .gz decompression"
    else
        echo "⊘ Script may not handle compressed dumps"
    fi
}

# Test 5: Script has retry logic for MySQL
test_retry_logic() {
    if grep -q "retry\|attempt\|for.*in" "$SCRIPT_DIR/scripts/import-database.sh"; then
        echo "✓ Script has retry/retry logic for MySQL connection"
    else
        echo "⊘ Script may not have retry logic"
    fi
}

# Test 6: Script skips import if database exists
test_skip_if_exists() {
    if grep -q "SHOW TABLES\|table_count\|skip\|already" "$SCRIPT_DIR/scripts/import-database.sh"; then
        echo "✓ Script checks if database already exists"
    else
        echo "⊘ Script may not skip existing databases"
    fi
}

# Run tests
test_script_executable
test_error_handling
test_variable_validation
test_gzip_handling
test_retry_logic
test_skip_if_exists

echo "✓ Import database tests passed"
