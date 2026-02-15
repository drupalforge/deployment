#!/bin/bash
# Comprehensive test runner - runs all test types
# This script orchestrates unit tests, Docker builds, and integration tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Track results
TESTS_FAILED=0
TESTS_PASSED=0

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          Drupal Forge Deployment - Complete Test Suite        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to run a test suite
run_test_suite() {
    local suite_name="$1"
    local test_command="$2"
    
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Running: $suite_name${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if eval "$test_command"; then
        echo ""
        echo -e "${GREEN}✓ $suite_name PASSED${NC}"
        ((TESTS_PASSED++))
    else
        echo ""
        echo -e "${RED}✗ $suite_name FAILED${NC}"
        ((TESTS_FAILED++))
    fi
    echo ""
}

# Run unit tests
run_test_suite "Unit Tests" "cd '$SCRIPT_DIR' && bash run-all-tests.sh"

# Run Docker build tests
run_test_suite "Docker Build Tests" "cd '$SCRIPT_DIR' && bash test-docker-build.sh"

# Run integration tests
run_test_suite "Integration Tests" "cd '$SCRIPT_DIR' && bash integration-test.sh"

# Summary
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                        Test Summary                            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Suites passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Suites failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All test suites passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some test suites failed${NC}"
    exit 1
fi
