#!/bin/bash
# Unit tests for deployment-entrypoint.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRYPOINT="$SCRIPT_DIR/scripts/deployment-entrypoint.sh"
TEMP_DIR=$(mktemp -d)
trap "sudo -n rm -rf $TEMP_DIR 2>/dev/null || rm -rf $TEMP_DIR" EXIT

# shellcheck source=lib/utils.sh
source "$TEST_DIR/lib/utils.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Testing deployment-entrypoint.sh...${NC}"

# Probe for sudo credentials when run standalone (not from unit-test.sh or run-all-tests.sh).
# SUDO_STATUS_FILE is exported by unit-test.sh before launching background test scripts,
# so its presence indicates an orchestrating parent is handling the probe.
if [ "${SUDO_PROBED:-}" != "1" ] && [ -z "${SUDO_STATUS_FILE:-}" ]; then
    SUDO_AVAILABLE=0
    if sudo -n true 2>/dev/null; then
        SUDO_AVAILABLE=1
        echo -e "${GREEN}✓ sudo credentials available${NC}"
        echo ""
    elif [ -t 0 ] && [ -z "${CI:-}" ]; then
        echo -e "${YELLOW}Some tests require sudo. Enter your password to run them,${NC}"
        echo -e "${YELLOW}or press Ctrl-C to skip (30 second timeout).${NC}"
        if _timeout 30 sudo -v; then
            SUDO_AVAILABLE=1
        fi
        if [ "$SUDO_AVAILABLE" = "0" ]; then
            echo -e "${YELLOW}No sudo credentials — sudo-dependent tests will be skipped.${NC}"
        fi
        echo ""
    fi
    export SUDO_AVAILABLE SUDO_PROBED=1
fi

# Several tests run the entrypoint which calls "sudo install" and "sudo chown"
# without -n.  If launched in parallel from unit-test.sh, the sudo probe may
# still be running; wait here (up to 35 s) so credentials are cached before
# any test invokes the entrypoint.
if [ -n "${SUDO_STATUS_FILE:-}" ]; then
    _sudo_wait=0
    while [ "$(cat "$SUDO_STATUS_FILE" 2>/dev/null)" = "pending" ] && [ "$_sudo_wait" -lt 350 ]; do
        sleep 0.1
        _sudo_wait=$((_sudo_wait + 1))
    done
fi

# Read the probe result written by unit-test.sh or run-all-tests.sh.
# This is used as a fast short-circuit: if the parent probe found no sudo we can
# skip immediately without attempting sudo -n true in the current process context.
# Note: per-test checks also call sudo -n true directly as a runtime verification
# that credentials are usable in the current process (e.g. when this script is run
# standalone or when sudo credentials have expired between tests).
_sudo_avail="${SUDO_AVAILABLE:-0}"
if [ -n "${SUDO_STATUS_FILE:-}" ]; then
    _sf_val=$(cat "$SUDO_STATUS_FILE" 2>/dev/null || echo "0")
    [ "$_sf_val" = "1" ] && _sudo_avail=1
fi

# Test 1: Script is executable
test_script_executable() {
    if [ -x "$ENTRYPOINT" ]; then
        echo -e "${GREEN}✓ deployment-entrypoint.sh is executable${NC}"
    else
        echo -e "${RED}✗ deployment-entrypoint.sh is not executable${NC}"
        exit 1
    fi
}

# Test 2: Script has error handling
test_error_handling() {
    if grep -q "set -e" "$ENTRYPOINT"; then
        echo -e "${GREEN}✓ Script has error handling (set -e)${NC}"
    else
        echo -e "${YELLOW}⊘ Script missing 'set -e'${NC}"
    fi
}

# Test 3: Script has APP_ROOT wait loop
test_app_root_wait_present() {
    if grep -q "APP_ROOT_TIMEOUT" "$ENTRYPOINT"; then
        echo -e "${GREEN}✓ Script has APP_ROOT wait logic${NC}"
    else
        echo -e "${RED}✗ Script missing APP_ROOT_TIMEOUT wait logic${NC}"
        exit 1
    fi
}

# Test 4: Wait is skipped when APP_ROOT_TIMEOUT=0
test_app_root_wait_skipped_at_zero() {
    local app_root="$TEMP_DIR/empty-root-zero"
    mkdir -p "$app_root"
    if [ "${_sudo_avail:-0}" != "1" ] || ! sudo -n true 2>/dev/null; then
        echo -e "${YELLOW}⊘ Skipping: passwordless sudo not available${NC}"
        return 0
    fi

    # With timeout=0 the script should proceed immediately without waiting.
    # We pass a no-op command so exec succeeds without starting Apache.
    local start end elapsed
    start=$(date +%s)
    set +e
    APP_ROOT="$app_root" APP_ROOT_TIMEOUT=0 BOOTSTRAP_REQUIRED=no \
        bash "$ENTRYPOINT" true >/dev/null 2>&1
    set -e
    end=$(date +%s)
    elapsed=$((end - start))

    if [ "$elapsed" -lt 5 ]; then
        echo -e "${GREEN}✓ APP_ROOT_TIMEOUT=0 skips waiting${NC}"
    else
        echo -e "${RED}✗ APP_ROOT_TIMEOUT=0 should skip waiting (took ${elapsed}s)${NC}"
        exit 1
    fi
}

# Test 5: Script proceeds immediately when APP_ROOT is non-empty
test_app_root_ready_immediately() {
    local app_root="$TEMP_DIR/populated-root"
    mkdir -p "$app_root"
    touch "$app_root/composer.json"
    if [ "${_sudo_avail:-0}" != "1" ] || ! sudo -n true 2>/dev/null; then
        echo -e "${YELLOW}⊘ Skipping: passwordless sudo not available${NC}"
        return 0
    fi

    local start end elapsed
    start=$(date +%s)
    set +e
    APP_ROOT="$app_root" APP_ROOT_TIMEOUT=30 BOOTSTRAP_REQUIRED=no \
        bash "$ENTRYPOINT" true >/dev/null 2>&1
    set -e
    end=$(date +%s)
    elapsed=$((end - start))

    if [ "$elapsed" -lt 5 ]; then
        echo -e "${GREEN}✓ Script proceeds immediately when APP_ROOT is already populated${NC}"
    else
        echo -e "${RED}✗ Script should not wait when APP_ROOT is already populated (took ${elapsed}s)${NC}"
        exit 1
    fi
}

# Test 6: Timeout warning is logged when APP_ROOT remains empty
test_app_root_timeout_warning() {
    local app_root="$TEMP_DIR/empty-root-timeout"
    mkdir -p "$app_root"
    if [ "${_sudo_avail:-0}" != "1" ] || ! sudo -n true 2>/dev/null; then
        echo -e "${YELLOW}⊘ Skipping: passwordless sudo not available${NC}"
        return 0
    fi

    local output
    set +e
    output=$(APP_ROOT="$app_root" APP_ROOT_TIMEOUT=1 BOOTSTRAP_REQUIRED=no \
        bash "$ENTRYPOINT" true 2>&1)
    set -e

    if echo "$output" | grep -q "Warning:"; then
        echo -e "${GREEN}✓ Timeout warning logged when APP_ROOT remains empty${NC}"
    else
        echo -e "${RED}✗ Expected timeout warning in output${NC}"
        echo "$output"
        exit 1
    fi
}

# Test 7: Root-owned entries (e.g. lost+found) are ignored when waiting for APP_ROOT
test_app_root_ignores_root_owned_entries() {
    local app_root="$TEMP_DIR/root-owned-root"
    mkdir -p "$app_root"
    # This test requires sudo.
    if [ "${_sudo_avail:-0}" != "1" ] || ! sudo -n true 2>/dev/null; then
        echo -e "${YELLOW}⊘ Skipping: passwordless sudo not available${NC}"
        return 0
    fi
    # Create a root-owned lost+found directory (simulates the mounted volume filesystem)
    sudo -n mkdir -p "$app_root/lost+found"
    sudo -n chown root "$app_root/lost+found"

    local output
    set +e
    output=$(APP_ROOT="$app_root" APP_ROOT_TIMEOUT=1 BOOTSTRAP_REQUIRED=no \
        bash "$ENTRYPOINT" true 2>&1)
    set -e

    # Script should treat the directory as empty (only root-owned content) and log a warning
    if echo "$output" | grep -q "Warning:"; then
        echo -e "${GREEN}✓ Root-owned entries (lost+found) are ignored when checking if APP_ROOT is empty${NC}"
    else
        echo -e "${RED}✗ Expected timeout warning when APP_ROOT contains only root-owned entries${NC}"
        echo "$output"
        exit 1
    fi
}

# Test 8: Proxy path directories are created unconditionally after bootstrap
test_proxy_path_directory_creation() {
    if grep -q "install -d\|mkdir -p" "$ENTRYPOINT" && \
       grep -q "chown" "$ENTRYPOINT"; then
        echo -e "${GREEN}✓ Entrypoint creates and sets ownership of proxy path directories${NC}"
    else
        echo -e "${RED}✗ Entrypoint missing proxy path directory creation${NC}"
        exit 1
    fi
}

# Run tests
test_script_executable
test_error_handling
test_app_root_wait_present
test_app_root_wait_skipped_at_zero
test_app_root_ready_immediately
test_app_root_timeout_warning
test_app_root_ignores_root_owned_entries
test_proxy_path_directory_creation

echo -e "${GREEN}✓ Deployment entrypoint tests passed${NC}"
