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

# shellcheck source=lib/sudo.sh
source "$SCRIPT_DIR/lib/sudo.sh"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          Drupal Forge Deployment - Complete Test Suite         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Probe for sudo credentials before launching tests.
# Unit tests need sudo for some tests. By using the library function,
# credentials are cached before the tests that need them.
TMPDIR_SUITES=$(mktemp -d)
setup_sudo "$TMPDIR_SUITES"

# Print results for a suite immediately when it completes.
TESTS_FAILED=0
TESTS_PASSED=0
# Tracks how many "Starting:" placeholder lines are on screen so they can be
# erased and replaced by the results section in interactive terminals.
PENDING_LINES=0

print_suite() {
    local suite_name="$1"
    local out_file="$2"
    local exit_code="$3"

    # In interactive terminals, erase the "Starting:" placeholder lines printed
    # before this suite started so results appear in their place.
    # \033[%dA = cursor up N lines; \033[J = erase from cursor to end of screen.
    if is_interactive_terminal && [ "${PENDING_LINES:-0}" -gt 0 ]; then
        printf "\033[%dA\033[J" "$PENDING_LINES"
        PENDING_LINES=0
    fi

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
PENDING_LINES=$((PENDING_LINES + 1))
( bash_exit=0
  cd "$SCRIPT_DIR" && bash unit-test.sh > "$TMPDIR_SUITES/unit-tests.txt" 2>&1 || bash_exit=$?
  echo "$bash_exit" > "$TMPDIR_SUITES/exit-unit-tests.txt" ) &
UNIT_TESTS_PID=$!

# Docker build tests run in parallel with unit tests, but integration tests
# wait for Docker build to finish (both use the same test-df-deployment:8.3 image tag).
echo -e "${YELLOW}Starting: Docker Build Tests${NC}"
PENDING_LINES=$((PENDING_LINES + 1))
( bash_exit=0
  cd "$SCRIPT_DIR" && bash docker-build-test.sh > "$TMPDIR_SUITES/docker-build-tests.txt" 2>&1 || bash_exit=$?
  echo "$bash_exit" > "$TMPDIR_SUITES/exit-docker-build-tests.txt" ) &
DOCKER_BUILD_PID=$!

echo ""
PENDING_LINES=$((PENDING_LINES + 1))  # Account for the blank line above

# Print results as each suite completes.
# Unit tests are fast (~seconds); wait for them first so their output appears early.
wait "$UNIT_TESTS_PID" || true
unit_exit=$(cat "$TMPDIR_SUITES/exit-unit-tests.txt" 2>/dev/null || echo 1)
print_suite "Unit Tests" "$TMPDIR_SUITES/unit-tests.txt" "$unit_exit"

# Wait for Docker build tests (minutes); print immediately when done.
wait "$DOCKER_BUILD_PID" || true
docker_build_exit=$(cat "$TMPDIR_SUITES/exit-docker-build-tests.txt" 2>/dev/null || echo 1)
print_suite "Docker Build Tests" "$TMPDIR_SUITES/docker-build-tests.txt" "$docker_build_exit"

# Run integration tests after Docker build (shared image tag).
# Stream output directly to the terminal (no file redirect) so that Docker
# Compose detects the TTY and preserves the blue color in build progress output.
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Results: Integration Tests${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
integration_exit=0
(cd "$SCRIPT_DIR" && bash integration-test.sh) || integration_exit=$?
echo ""
if [ "$integration_exit" -eq 0 ]; then
    echo -e "${GREEN}✓ Integration Tests PASSED${NC}"
    ((TESTS_PASSED+=1))
else
    echo -e "${RED}✗ Integration Tests FAILED${NC}"
    ((TESTS_FAILED+=1))
fi
echo ""

# Summary (cleanup trap will run before exit)
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
