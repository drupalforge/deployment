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

# shellcheck source=lib/utils.sh
source "$SCRIPT_DIR/lib/utils.sh"

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Drupal Forge Deployment Tests${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Launch all test suites in parallel first so that non-sudo tests start
# running immediately, before (and during) the sudo credential probe below.
# A flag file (SUDO_STATUS_FILE) is written once the probe completes so that
# sudo-requiring tests can wait for the final result instead of racing.
TMPDIR_TESTS=$(mktemp -d)
SUDO_STATUS_FILE="$TMPDIR_TESTS/sudo-status"
echo "pending" > "$SUDO_STATUS_FILE"
export SUDO_STATUS_FILE

declare -a PIDS=()
declare -a TEST_NAMES=()
declare -a OUT_FILES=()

for test_file in "$TEST_DIR"/test-*.sh; do
    [ -f "$test_file" ] || continue
    test_name=$(basename "$test_file" .sh)
    out_file="$TMPDIR_TESTS/output-${test_name}.txt"
    TEST_NAMES+=("$test_name")
    OUT_FILES+=("$out_file")
    ( bash "$test_file" > "$out_file" 2>&1; echo $? > "$TMPDIR_TESTS/exit-${test_name}.txt" ) &
    PIDS+=($!)
done

# Probe for sudo credentials now that non-sudo tests are already running.
# Skip the probe if a parent script (e.g. run-all-tests.sh) already ran it.
if [ "${SUDO_AVAILABLE:-}" != "1" ]; then
    SUDO_AVAILABLE=0
    if sudo -n true 2>/dev/null; then
        SUDO_AVAILABLE=1
    elif [ -t 0 ]; then
        echo -e "${YELLOW}Some tests require sudo. Enter your password to run them,${NC}"
        echo -e "${YELLOW}or wait 30 seconds / press Ctrl-C to skip those tests.${NC}"
        # Show a countdown on the terminal while waiting for the password.
        ( for i in $(seq 29 -1 1); do
              sleep 1
              printf "\r  (%2d seconds remaining) " "$i" > /dev/tty 2>/dev/null || true
          done
          printf "\r%-40s\r" "" > /dev/tty 2>/dev/null || true
        ) &
        COUNTDOWN_PID=$!
        if _timeout 30 sudo -v; then
            SUDO_AVAILABLE=1
        fi
        kill "$COUNTDOWN_PID" 2>/dev/null
        wait "$COUNTDOWN_PID" 2>/dev/null
        printf "\r%-40s\r" "" 2>/dev/null || true
        if [ "$SUDO_AVAILABLE" = "0" ]; then
            echo -e "${YELLOW}No sudo credentials — sudo-dependent tests will be skipped.${NC}"
        fi
        echo ""
    fi
fi
export SUDO_AVAILABLE

# Signal any tests that are polling the flag file.
echo "$SUDO_AVAILABLE" > "$SUDO_STATUS_FILE"

# Wait for each suite, then print its buffered output in order
failed_tests=0
passed_suites=0

for i in "${!TEST_NAMES[@]}"; do
    test_name="${TEST_NAMES[$i]}"
    wait "${PIDS[$i]}"
    echo -e "${YELLOW}Running $test_name...${NC}"
    cat "${OUT_FILES[$i]}"
    exit_code=$(cat "$TMPDIR_TESTS/exit-${test_name}.txt" 2>/dev/null || echo 1)
    if [ "$exit_code" -eq 0 ]; then
        echo -e "${GREEN}✓ $test_name passed${NC}"
        passed_suites=$((passed_suites + 1))
    else
        echo -e "${RED}✗ $test_name failed${NC}"
        failed_tests=$((failed_tests + 1))
    fi
    echo ""
done

rm -rf "$TMPDIR_TESTS"

# Summary
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
echo ""

if [ $failed_tests -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
