#!/bin/bash
# Unit test runner - runs syntax and pattern validation tests
#
# NOTE: These tests check syntax and patterns in files (grep-based validation).
# They do NOT build Docker images or run integration tests.
# 
# For full validation including Docker builds, see tests/README.md
# or run: bash run-all-tests.sh
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================"
echo "Drupal Forge Deployment Tests"
echo "================================"
echo ""

# Track test results
failed_tests=0
passed_suites=0

# Function to run a test suite
run_test_suite() {
    local test_file="$1"
    local test_name=$(basename "$test_file" .sh)
    
    echo -e "${YELLOW}Running $test_name...${NC}"
    if bash "$test_file"; then
        echo -e "${GREEN}✓ $test_name passed${NC}"
        passed_suites=$((passed_suites + 1))
        echo ""
    else
        echo -e "${RED}✗ $test_name failed${NC}"
        failed_tests=$((failed_tests + 1))
        echo ""
    fi
}

# Find and run all unit test files (test-*.sh pattern)
for test_file in "$TEST_DIR"/test-*.sh; do
    if [ -f "$test_file" ]; then
        run_test_suite "$test_file"
    fi
done

# Summary
echo "================================"
echo "Test Summary"
echo "================================"
echo "Suites passed: $((passed_suites))"
echo "Suites failed: $((failed_tests))"
echo ""

if [ $failed_tests -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
