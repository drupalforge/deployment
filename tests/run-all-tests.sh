#!/bin/bash
# Comprehensive test runner - runs all test types
# This script orchestrates unit tests, Docker builds, and integration tests.
#
# Parallelism:
#   - Unit tests run concurrently with the Docker-based test suite.
#   - Docker build tests and integration tests run sequentially within their
#     suite because both build/use the same test-df-deployment:8.3 image tag.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# shellcheck source=lib/utils.sh
source "$SCRIPT_DIR/lib/utils.sh"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          Drupal Forge Deployment - Complete Test Suite         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Probe for sudo credentials before launching tests.
# Unit tests need sudo for some tests. By probing here with a clear message
# and a countdown, credentials are cached before the tests that need them.
SUDO_AVAILABLE=0
TMPDIR_SUITES=$(mktemp -d)
if sudo -n true 2>/dev/null; then
    SUDO_AVAILABLE=1
    echo -e "${GREEN}✓ sudo credentials available${NC}"
    echo ""
elif [ -t 0 ] && [ -z "${CI:-}" ]; then
    echo -e "${YELLOW}Some tests require sudo. Enter your password to run them,${NC}"
    echo -e "${YELLOW}or press Ctrl-C to skip (30 second timeout).${NC}"
    COUNTDOWN_STOP_FILE="$TMPDIR_SUITES/countdown-stop"
    printf "  (30 sec remaining)\n" > /dev/tty 2>/dev/null || true
    ( for i in $(seq 30 -1 1); do
          sleep 1
          [ -f "$COUNTDOWN_STOP_FILE" ] && break
          printf "\033[s\033[A\r  (%2d sec remaining)\033[u" "$i" > /dev/tty 2>/dev/null || true
      done
    ) &
    COUNTDOWN_PID=$!
    if _timeout 30 sudo -v; then
        SUDO_AVAILABLE=1
    fi
    touch "$COUNTDOWN_STOP_FILE"
    kill "$COUNTDOWN_PID" 2>/dev/null || true
    wait "$COUNTDOWN_PID" 2>/dev/null || true
    # sudo always writes "Password:" in this branch (sudo -n failed to get here).
    # After the user interacts, cursor is 2 lines below the countdown line.
    # Go up 2 and erase to end of screen to remove countdown + password lines.
    printf "\033[2A\r\033[J" > /dev/tty 2>/dev/null || true
    if [ "$SUDO_AVAILABLE" = "0" ]; then
        echo -e "${YELLOW}No sudo credentials — sudo-dependent tests will be skipped.${NC}"
    fi
    echo ""
fi
export SUDO_AVAILABLE SUDO_PROBED=1

# Print results for a suite immediately when it completes.
TESTS_FAILED=0
TESTS_PASSED=0

print_suite() {
    local suite_name="$1"
    local out_file="$2"
    local exit_code="$3"

    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Results: $suite_name${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    cat "$out_file"
    echo ""
    if [ "$exit_code" -eq 0 ]; then
        echo -e "${GREEN}✓ $suite_name PASSED${NC}"
        ((TESTS_PASSED+=1))
    else
        echo -e "${RED}✗ $suite_name FAILED${NC}"
        ((TESTS_FAILED+=1))
    fi
    echo ""
}

# Unit tests run concurrently with Docker-based tests.
# Use "bash_exit=0; cmd || bash_exit=$?" so the exit file is always written
# even when set -e is active in the subshell and the command fails.
echo -e "${YELLOW}Starting: Unit Tests${NC}"
( bash_exit=0
  cd "$SCRIPT_DIR" && bash unit-test.sh > "$TMPDIR_SUITES/unit-tests.txt" 2>&1 || bash_exit=$?
  echo "$bash_exit" > "$TMPDIR_SUITES/exit-unit-tests.txt" ) &
UNIT_TESTS_PID=$!

# Docker build tests run in parallel with unit tests, but integration tests
# wait for Docker build to finish (both use the same test-df-deployment:8.3 image tag).
echo -e "${YELLOW}Starting: Docker Build Tests${NC}"
( bash_exit=0
  cd "$SCRIPT_DIR" && bash docker-build-test.sh > "$TMPDIR_SUITES/docker-build-tests.txt" 2>&1 || bash_exit=$?
  echo "$bash_exit" > "$TMPDIR_SUITES/exit-docker-build-tests.txt" ) &
DOCKER_BUILD_PID=$!

echo ""

# Print results as each suite completes.
# Unit tests are fast (~seconds); wait for them first so their output appears early.
wait "$UNIT_TESTS_PID" || true
unit_exit=$(cat "$TMPDIR_SUITES/exit-unit-tests.txt" 2>/dev/null || echo 1)
print_suite "Unit Tests" "$TMPDIR_SUITES/unit-tests.txt" "$unit_exit"

# Wait for Docker build tests (minutes); print immediately when done.
wait "$DOCKER_BUILD_PID" || true
docker_build_exit=$(cat "$TMPDIR_SUITES/exit-docker-build-tests.txt" 2>/dev/null || echo 1)
print_suite "Docker Build Tests" "$TMPDIR_SUITES/docker-build-tests.txt" "$docker_build_exit"

# Run integration tests after Docker build (shared image tag); print when done.
echo -e "${YELLOW}Starting: Integration Tests${NC}"
echo ""
( bash_exit=0
  cd "$SCRIPT_DIR" && bash integration-test.sh > "$TMPDIR_SUITES/integration-tests.txt" 2>&1 || bash_exit=$?
  echo "$bash_exit" > "$TMPDIR_SUITES/exit-integration-tests.txt" ) &
INTEGRATION_PID=$!
wait "$INTEGRATION_PID" || true
integration_exit=$(cat "$TMPDIR_SUITES/exit-integration-tests.txt" 2>/dev/null || echo 1)
print_suite "Integration Tests" "$TMPDIR_SUITES/integration-tests.txt" "$integration_exit"

rm -rf "$TMPDIR_SUITES"

# Summary
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                        Test Summary                            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
if [ $TESTS_PASSED -eq 0 ]; then
    echo "Suites passed: $TESTS_PASSED"
else
    echo -e "Suites passed: ${GREEN}$TESTS_PASSED${NC}"
fi

if [ $TESTS_FAILED -eq 0 ]; then
    echo "Suites failed: $TESTS_FAILED"
else
    echo -e "Suites failed: ${RED}$TESTS_FAILED${NC}"
fi
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All test suites passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some test suites failed${NC}"
    exit 1
fi
