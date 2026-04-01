#!/bin/bash
# Unit tests for deployment-entrypoint.sh
set -e

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${TEST_DIR%/*}"
ENTRYPOINT="$SCRIPT_DIR/scripts/deployment-entrypoint.sh"
TEMP_DIR=$(mktemp -d)

# shellcheck source=lib/sudo.sh
source "$TEST_DIR/lib/sudo.sh"

echo -e "${BLUE}Testing deployment-entrypoint.sh...${NC}"

# Setup sudo credentials and background refresh
setup_sudo "$TEMP_DIR"

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
    local fake_bin="$TEMP_DIR/fake-sudo-zero"

    mkdir -p "$app_root"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/sudo" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$fake_bin/sudo"

    # With timeout=0 the script should proceed immediately without waiting.
    # We pass a no-op command so exec succeeds without starting Apache.
    local start end elapsed
    start=$(date +%s)
    set +e
    PATH="$fake_bin:$PATH" APP_ROOT="$app_root" APP_ROOT_TIMEOUT=0 BOOTSTRAP_REQUIRED=no FILE_PROXY_PATHS="" \
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
    local fake_bin="$TEMP_DIR/fake-sudo-ready"

    mkdir -p "$app_root"
    mkdir -p "$fake_bin"
    cd "$app_root"
    git init . >/dev/null 2>&1
    git config user.email "test@test.local"
    git config user.name "Test"
    touch "$app_root/composer.json"
    git add composer.json >/dev/null 2>&1
    git commit -m "initial" >/dev/null 2>&1
    cat > "$fake_bin/sudo" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$fake_bin/sudo"

    local start end elapsed
    start=$(date +%s)
    set +e
    PATH="$fake_bin:$PATH" APP_ROOT="$app_root" APP_ROOT_TIMEOUT=30 BOOTSTRAP_REQUIRED=no FILE_PROXY_PATHS="" \
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

# Test 6: APP_ROOT without .git times out and fails startup
test_app_root_without_git_times_out() {
    local app_root="$TEMP_DIR/empty-root-timeout"
    local fake_bin="$TEMP_DIR/fake-sudo-no-git"

    mkdir -p "$app_root"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/sudo" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$fake_bin/sudo"

    local output
    set +e
    output=$(PATH="$fake_bin:$PATH" APP_ROOT="$app_root" APP_ROOT_TIMEOUT=1 BOOTSTRAP_REQUIRED=no FILE_PROXY_PATHS="" \
        bash "$ENTRYPOINT" true 2>&1)
    local status=$?
    set -e

    if [ "$status" -ne 0 ] && echo "$output" | grep -q "failing startup"; then
        echo -e "${GREEN}✓ APP_ROOT without .git timeout fails startup${NC}"
    else
        echo -e "${RED}✗ APP_ROOT without .git timeout should fail startup${NC}"
        echo "$output"
        exit 1
    fi
}

# Test 7: Timeout fails startup when APP_ROOT has .git but git HEAD is not ready
test_app_root_git_not_ready_timeout_failure() {
    local app_root="$TEMP_DIR/git-not-ready-root"
    local fake_bin="$TEMP_DIR/fake-sudo-git-not-ready"

    mkdir -p "$app_root"
    mkdir -p "$fake_bin"
    cd "$app_root"
    git init . >/dev/null 2>&1
    cat > "$fake_bin/sudo" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$fake_bin/sudo"

    local output
    set +e
    output=$(PATH="$fake_bin:$PATH" APP_ROOT="$app_root" APP_ROOT_TIMEOUT=1 BOOTSTRAP_REQUIRED=no FILE_PROXY_PATHS="" \
        bash "$ENTRYPOINT" true 2>&1)
    local status=$?
    set -e

    if [ "$status" -ne 0 ] && echo "$output" | grep -q "failing startup"; then
        echo -e "${GREEN}✓ APP_ROOT git HEAD timeout fails startup${NC}"
    else
        echo -e "${RED}✗ APP_ROOT git HEAD timeout should fail startup${NC}"
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

# Test 9: DRUSH_OPTIONS_URI is exported when DP_HOSTNAME is set.
# Requires sudo because the entrypoint unconditionally runs `sudo -n chown` on
# the proxy path directories. Uses the invoking user's identity instead of
# www-data so the test works on macOS where www-data does not exist.
test_drush_options_uri_exported_from_dp_hostname() {
    if ! ensure_active_sudo; then
        echo -e "${YELLOW}⊘ Skipped: DRUSH_OPTIONS_URI export test requires sudo${NC}"
        return 0
    fi

    local app_root="$TEMP_DIR/drush-uri-root"
    local web_root="$TEMP_DIR/drush-uri-web"
    local uri_file="$TEMP_DIR/drush-uri-value.txt"
    mkdir -p "$app_root"
    touch "$app_root/composer.json"

    set +e
    APP_ROOT="$app_root" APP_ROOT_TIMEOUT=0 BOOTSTRAP_REQUIRED=no \
        WEB_ROOT="$web_root" \
        APACHE_RUN_USER="$(id -un)" APACHE_RUN_GROUP="$(id -gn)" \
        DP_HOSTNAME="example.drupalforge.org" \
        bash "$ENTRYPOINT" bash -c "echo \"\$DRUSH_OPTIONS_URI\" > \"$uri_file\"" >/dev/null 2>&1
    set -e

    local uri
    uri="$(cat "$uri_file" 2>/dev/null | tr -d '\r\n[:space:]')"

    if [ "$uri" = "example.drupalforge.org" ]; then
        echo -e "${GREEN}✓ DRUSH_OPTIONS_URI is exported from DP_HOSTNAME${NC}"
    else
        echo -e "${RED}✗ DRUSH_OPTIONS_URI was not set from DP_HOSTNAME (got: $uri)${NC}"
        exit 1
    fi
}

# Test 10: DRUSH_OPTIONS_URI is not set when DP_HOSTNAME is absent.
# Requires sudo for the same reason as test 8.
test_drush_options_uri_unset_without_dp_hostname() {
    if ! ensure_active_sudo; then
        echo -e "${YELLOW}⊘ Skipped: DRUSH_OPTIONS_URI absent test requires sudo${NC}"
        return 0
    fi

    local app_root="$TEMP_DIR/drush-uri-no-hostname-root"
    local web_root="$TEMP_DIR/drush-uri-no-hostname-web"
    local uri_file="$TEMP_DIR/drush-uri-no-hostname-value.txt"
    mkdir -p "$app_root"
    touch "$app_root/composer.json"

    set +e
    APP_ROOT="$app_root" APP_ROOT_TIMEOUT=0 BOOTSTRAP_REQUIRED=no \
        WEB_ROOT="$web_root" \
        APACHE_RUN_USER="$(id -un)" APACHE_RUN_GROUP="$(id -gn)" \
        bash "$ENTRYPOINT" bash -c "echo \"\${DRUSH_OPTIONS_URI:-not_set}\" > \"$uri_file\"" >/dev/null 2>&1
    set -e

    local uri
    uri="$(cat "$uri_file" 2>/dev/null | tr -d '\r\n[:space:]')"

    if [ "$uri" = "not_set" ]; then
        echo -e "${GREEN}✓ DRUSH_OPTIONS_URI is not set when DP_HOSTNAME is absent${NC}"
    else
        echo -e "${RED}✗ DRUSH_OPTIONS_URI was unexpectedly set without DP_HOSTNAME (got: $uri)${NC}"
        exit 1
    fi
}

# Run tests
test_script_executable
test_error_handling
# Sudo-dependent tests first (shortest to longest expected runtime)
test_drush_options_uri_exported_from_dp_hostname
test_drush_options_uri_unset_without_dp_hostname

# Non-sudo tests
test_app_root_ready_immediately
test_app_root_wait_skipped_at_zero
test_app_root_without_git_times_out
test_app_root_git_not_ready_timeout_failure
test_app_root_wait_present
test_proxy_path_directory_creation

echo -e "${GREEN}✓ Deployment entrypoint tests passed${NC}"
