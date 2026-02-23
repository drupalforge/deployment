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

# Create temp dir for test output, exit codes, and the sudo status file.
# Write "pending" now — tests start immediately and will poll this file
# before using sudo; the probe below writes the final value when it finishes.
TMPDIR_TESTS=$(mktemp -d)
SUDO_STATUS_FILE="$TMPDIR_TESTS/sudo-status"
echo "pending" > "$SUDO_STATUS_FILE"
export SUDO_STATUS_FILE

# Launch all test suites in parallel NOW (before the probe) so non-sudo tests
# run immediately while we wait for the password.  All output is buffered so
# nothing is printed until after the probe completes.
#
# test-deployment-entrypoint.sh is excluded from the parallel launch and instead
# run in the foreground after the sudo probe (see below).  On macOS the default
# sudo timestamp_type is "tty", which scopes credentials to the foreground
# process group of the terminal.  Background jobs (&) are in a different process
# group, so sudo -n true fails non-deterministically even when the parent shell
# successfully authenticated — causing a variable number (1–4) of tests to be
# skipped.  Running that test suite in the foreground puts it in the same process
# group as the terminal, making TTY-scoped credentials reliably available.
declare -a PIDS=()
declare -a TEST_NAMES=()
declare -a OUT_FILES=()
declare -a DEFERRED_TESTS=()

for test_file in "$TEST_DIR"/test-*.sh; do
    [ -f "$test_file" ] || continue
    test_name=$(basename "$test_file" .sh)
    if [ "$test_name" = "test-deployment-entrypoint" ]; then
        DEFERRED_TESTS+=("$test_file")
        continue
    fi
    out_file="$TMPDIR_TESTS/output-${test_name}.txt"
    TEST_NAMES+=("$test_name")
    OUT_FILES+=("$out_file")
    ( bash_exit=0
      bash "$test_file" > "$out_file" 2>&1 || bash_exit=$?
      echo "$bash_exit" > "$TMPDIR_TESTS/exit-${test_name}.txt" ) &
    PIDS+=($!)
done
total_tests=$(( ${#TEST_NAMES[@]} + ${#DEFERRED_TESTS[@]} ))

# Probe for sudo credentials.  Skip if a parent script already ran the probe.
# The countdown loop also shows live test progress so the user knows work is
# happening while they wait for the password.
if [ "${SUDO_PROBED:-}" != "1" ]; then
    SUDO_AVAILABLE=0
    if sudo -n true 2>/dev/null; then
        SUDO_AVAILABLE=1
        echo -e "${GREEN}✓ sudo credentials available${NC}"
        echo ""
    elif [ -t 0 ] && [ -z "${CI:-}" ]; then
        done_count=$(ls "$TMPDIR_TESTS"/exit-*.txt 2>/dev/null | wc -l | tr -d ' ')
        echo -e "${YELLOW}Some tests require sudo. Enter your password to run them,${NC}"
        echo -e "${YELLOW}or press Ctrl-C to skip (30 second timeout, ${done_count}/${total_tests} tests already running).${NC}"
        # Print one countdown line, then each tick uses ANSI save/restore cursor
        # (\033[s/\033[u) so "Password:" stays below the countdown and the cursor
        # returns to exactly where sudo left it (after "Password: ").
        # A stop-flag file prevents one extra tick from firing after the user
        # presses Enter (which shifts the cursor and would overwrite the password line).
        COUNTDOWN_STOP_FILE="$TMPDIR_TESTS/countdown-stop"
        printf "  (30 sec remaining) [%d/%d tests done]\n" "$done_count" "$total_tests" > /dev/tty 2>/dev/null || true
        ( for i in $(seq 30 -1 1); do
              sleep 1
              [ -f "$COUNTDOWN_STOP_FILE" ] && break
              done_count=$(ls "$TMPDIR_TESTS"/exit-*.txt 2>/dev/null | wc -l | tr -d ' ')
              printf "\033[s\033[A\r  (%2d sec remaining) [%d/%d tests done]\033[u" "$i" "$done_count" "$total_tests" > /dev/tty 2>/dev/null || true
          done
        ) &
        COUNTDOWN_PID=$!
        if _timeout 30 sudo -v; then
            SUDO_AVAILABLE=1
        fi
        touch "$COUNTDOWN_STOP_FILE"
        kill "$COUNTDOWN_PID" 2>/dev/null || true
        wait "$COUNTDOWN_PID" 2>/dev/null || true
        rm -f "$COUNTDOWN_STOP_FILE"
        # sudo always writes "Password:" in this branch (sudo -n failed to get here).
        # After the user interacts, cursor is 2 lines below the countdown line.
        # Go up 2 and erase to end of screen to remove countdown + password lines.
        printf "\033[2A\r\033[J" > /dev/tty 2>/dev/null || true
        if [ "$SUDO_AVAILABLE" = "0" ]; then
            echo -e "${YELLOW}No sudo credentials — sudo-dependent tests will be skipped.${NC}"
        fi
        echo ""
    fi
fi
export SUDO_AVAILABLE SUDO_PROBED=1

# Signal any tests that are polling the flag file.
echo "$SUDO_AVAILABLE" > "$SUDO_STATUS_FILE"

# Run deferred tests (those requiring sudo) in the current foreground process so
# that TTY-scoped sudo credentials are available on macOS (tty_tickets policy).
for _deferred_test in "${DEFERRED_TESTS[@]}"; do
    _deferred_name=$(basename "$_deferred_test" .sh)
    _deferred_out="$TMPDIR_TESTS/output-${_deferred_name}.txt"
    _deferred_exit=0
    bash "$_deferred_test" > "$_deferred_out" 2>&1 || _deferred_exit=$?
    echo "$_deferred_exit" > "$TMPDIR_TESTS/exit-${_deferred_name}.txt"
    TEST_NAMES+=("$_deferred_name")
    OUT_FILES+=("$_deferred_out")
    PIDS+=("")  # Deferred test ran synchronously above; empty entry keeps array indices aligned with TEST_NAMES
done

# Wait for ALL parallel tests to finish before printing results.
for i in "${!TEST_NAMES[@]}"; do
    [ -n "${PIDS[$i]}" ] && { wait "${PIDS[$i]}" || true; }
done

# Print each suite's buffered output in order.
failed_tests=0
passed_suites=0

for i in "${!TEST_NAMES[@]}"; do
    test_name="${TEST_NAMES[$i]}"
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
