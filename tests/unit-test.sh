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
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# shellcheck source=lib/sudo.sh
source "$SCRIPT_DIR/lib/sudo.sh"

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Drupal Forge Deployment Tests${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Create temp dir for test output and exit codes.
TMPDIR_TESTS=$(mktemp -d)

# Setup sudo credentials with interactive countdown if needed, start background refresh, and setup cleanup.
setup_sudo "$TMPDIR_TESTS"

# Launch all test suites in parallel.  All output is buffered so nothing is
# printed until after all suites finish.
declare -a PIDS=()
declare -a TEST_NAMES=()
declare -a OUT_FILES=()
declare -a EXIT_CODES=()

for test_file in "$TEST_DIR"/test-*.sh; do
    [ -f "$test_file" ] || continue
    test_name=$(basename "$test_file" .sh)
    out_file="$TMPDIR_TESTS/output-${test_name}.txt"
    TEST_NAMES+=("$test_name")
    OUT_FILES+=("$out_file")
    bash "$test_file" > "$out_file" 2>&1 &
    PIDS+=($!)
done

# Wait for ALL parallel tests to finish before printing results.
for i in "${!TEST_NAMES[@]}"; do
    if wait "${PIDS[$i]}"; then
        EXIT_CODES[$i]=0
    else
        EXIT_CODES[$i]=$?
    fi
done

# Print each suite's buffered output in order.

failed_tests=0
passed_suites=0
skipped_assertions=0

for i in "${!TEST_NAMES[@]}"; do
    test_name="${TEST_NAMES[$i]}"
    echo -e "${YELLOW}Running $test_name...${NC}"
    cat "${OUT_FILES[$i]}"
    skips_in_suite=$(awk '/⊘ /{c++} END{print c+0}' "${OUT_FILES[$i]}")
    skipped_assertions=$((skipped_assertions + skips_in_suite))
    exit_code="${EXIT_CODES[$i]:-1}"
    if [ "$exit_code" -eq 0 ]; then
        echo -e "${GREEN}✓ $test_name passed${NC}"
        passed_suites=$((passed_suites + 1))
    else
        echo -e "${RED}✗ $test_name failed${NC}"
        failed_tests=$((failed_tests + 1))
    fi
    echo ""
done

# Summary (cleanup trap will run before exit)
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}================================${NC}"
if [ $passed_suites -eq 0 ]; then
    echo "Suites passed: $((passed_suites))"
else
    echo -e "Suites passed: ${GREEN}$((passed_suites))${NC}"
fi

if [ $failed_tests -eq 0 ]; then
    echo "Suites failed: $((failed_tests))"
else
    echo -e "Suites failed: ${RED}$((failed_tests))${NC}"
fi

if [ $skipped_assertions -gt 0 ]; then
    echo -e "Assertions skipped: ${YELLOW}$((skipped_assertions))${NC}"
fi
echo ""

if [ $failed_tests -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
