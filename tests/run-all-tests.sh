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
if sudo -n true 2>/dev/null; then
    SUDO_AVAILABLE=1
elif [ -t 0 ] && [ -z "${CI:-}" ]; then
    echo -e "${YELLOW}Some tests require sudo. Enter your password to run them,${NC}"
    echo -e "${YELLOW}or press Ctrl-C to skip (30 second timeout).${NC}"
    ( for i in $(seq 29 -1 1); do
          sleep 1
          printf "  (%2d sec remaining)\n" "$i" > /dev/tty 2>/dev/null || true
      done
    ) &
    COUNTDOWN_PID=$!
    if _timeout 30 sudo -v; then
        SUDO_AVAILABLE=1
    fi
    kill "$COUNTDOWN_PID" 2>/dev/null || true
    wait "$COUNTDOWN_PID" 2>/dev/null || true
    if [ "$SUDO_AVAILABLE" = "0" ]; then
        echo -e "${YELLOW}No sudo credentials — sudo-dependent tests will be skipped.${NC}"
    fi
    echo ""
fi
export SUDO_AVAILABLE SUDO_PROBED=1

TMPDIR_SUITES=$(mktemp -d)

# Run all suites in the background with output buffered; show a live status
# line so the user knows work is progressing without mixing output with prompts.
echo -e "${YELLOW}Starting: Unit Tests${NC}"
( cd "$SCRIPT_DIR" && bash unit-test.sh > "$TMPDIR_SUITES/unit-tests.txt" 2>&1
  echo $? > "$TMPDIR_SUITES/exit-unit-tests.txt" ) &
UNIT_TESTS_PID=$!

# Run Docker build tests then integration tests sequentially (shared image tag).
echo -e "${YELLOW}Starting: Docker Build Tests${NC}"
( cd "$SCRIPT_DIR" && bash docker-build-test.sh > "$TMPDIR_SUITES/docker-build-tests.txt" 2>&1
  echo $? > "$TMPDIR_SUITES/exit-docker-build-tests.txt" ) &
DOCKER_BUILD_PID=$!

echo -e "${YELLOW}Starting: Integration Tests (queued behind Docker Build)${NC}"

# Show a live "X/3 suites done" line while waiting for everything to finish.
if is_interactive_terminal; then
    ( while true; do
          done=0
          [ -f "$TMPDIR_SUITES/exit-unit-tests.txt" ]         && done=$((done+1))
          [ -f "$TMPDIR_SUITES/exit-docker-build-tests.txt" ] && done=$((done+1))
          [ -f "$TMPDIR_SUITES/exit-integration-tests.txt" ]  && done=$((done+1))
          printf "\r  Waiting for test suites... [%d/3 done] " "$done" > /dev/tty 2>/dev/null || true
          [ "$done" -ge 3 ] && break
          sleep 0.5
      done
      printf "\r%-60s\r" "" > /dev/tty 2>/dev/null || true
    ) &
    STATUS_PID=$!
fi

wait "$DOCKER_BUILD_PID" || true
docker_build_exit=$(cat "$TMPDIR_SUITES/exit-docker-build-tests.txt" 2>/dev/null || echo 1)

( cd "$SCRIPT_DIR" && bash integration-test.sh > "$TMPDIR_SUITES/integration-tests.txt" 2>&1
  echo $? > "$TMPDIR_SUITES/exit-integration-tests.txt" ) &
INTEGRATION_PID=$!
wait "$INTEGRATION_PID" || true
integration_exit=$(cat "$TMPDIR_SUITES/exit-integration-tests.txt" 2>/dev/null || echo 1)

# Now wait for unit tests to finish (likely already done)
wait "$UNIT_TESTS_PID" || true
unit_exit=$(cat "$TMPDIR_SUITES/exit-unit-tests.txt" 2>/dev/null || echo 1)

if [ -n "${STATUS_PID:-}" ]; then
    kill "$STATUS_PID" 2>/dev/null || true
    wait "$STATUS_PID" 2>/dev/null || true
    printf "\r%-60s\r" "" > /dev/tty 2>/dev/null || true
fi

# Print results for each suite in a consistent order
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

print_suite "Unit Tests"          "$TMPDIR_SUITES/unit-tests.txt"          "$unit_exit"
print_suite "Docker Build Tests"  "$TMPDIR_SUITES/docker-build-tests.txt"  "$docker_build_exit"
print_suite "Integration Tests"   "$TMPDIR_SUITES/integration-tests.txt"   "$integration_exit"

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
