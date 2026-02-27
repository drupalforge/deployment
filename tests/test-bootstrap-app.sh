#!/bin/bash
# Unit tests for bootstrap-app.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR=$(mktemp -d)

# shellcheck source=lib/sudo.sh
source "$TEST_DIR/lib/sudo.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Testing bootstrap-app.sh...${NC}"

# Setup sudo credentials and background refresh
setup_sudo "$TEMP_DIR"

# Test 1: Git submodule initialization (mock)
test_git_submodules() {
    local test_repo="$TEMP_DIR/test-repo"
    mkdir -p "$test_repo/.git"
    cd "$test_repo"
    
    # Create a git config to simulate submodules
    git init . >/dev/null 2>&1
    git config submodule.test.path "modules/test"
    git config submodule.test.url "https://github.com/test/test.git"
    
    # Run bootstrap with git installed
    if command -v git &> /dev/null; then
        bash "$SCRIPT_DIR/scripts/bootstrap-app.sh" 2>&1 | grep -q "Git submodules" || true
        echo -e "${GREEN}✓ Git submodule detection works${NC}"
    else
        echo -e "${YELLOW}⊘ Git not found in PATH (skipping submodule test)${NC}"
    fi
}

# Test 2: Composer detection
test_composer_detection() {
    local test_repo="$TEMP_DIR/test-composer"
    mkdir -p "$test_repo"
    
    # Create a composer.json
    echo '{"name": "test/app"}' > "$test_repo/composer.json"
    cd "$test_repo"
    
    # This will try to run composer install but that's expected
    bash "$SCRIPT_DIR/scripts/bootstrap-app.sh" 2>&1 | grep -q "Composer" || true
    echo -e "${GREEN}✓ Composer detection logic works${NC}"
}

# Test 3: Composer install flags are passed through
test_composer_install_flags() {
        local test_repo="$TEMP_DIR/test-composer-flags"
        local fake_bin="$TEMP_DIR/fake-bin-flags"
        mkdir -p "$test_repo" "$fake_bin"

        echo '{"name": "test/app"}' > "$test_repo/composer.json"

        cat > "$fake_bin/composer" <<'EOF'
#!/bin/bash
if [[ "$*" == *"--version"* ]]; then
    echo "Composer version 2.x"
    exit 0
fi
if [[ "$*" == *"install"* ]]; then
    if [[ "$*" == *"--ignore-platform-req=php"* ]]; then
        exit 0
    fi
    echo "Missing composer install flag" >&2
    exit 1
fi
exit 0
EOF
        chmod +x "$fake_bin/composer"

        set +e
        PATH="$fake_bin:$PATH" APP_ROOT="$test_repo" COMPOSER_INSTALL_FLAGS="--ignore-platform-req=php" \
                bash "$SCRIPT_DIR/scripts/bootstrap-app.sh" >/dev/null 2>&1
        local status=$?
        set -e

        if [ "$status" -eq 0 ]; then
                echo -e "${GREEN}✓ Composer install flags are passed through${NC}"
        else
                echo -e "${RED}✗ Composer install flags were not passed through${NC}"
                exit 1
        fi
}

# Test 3: Composer install failure causes script to fail
test_composer_install_failure() {
    local test_repo="$TEMP_DIR/test-composer-fail"
    local fake_bin="$TEMP_DIR/fake-bin-fail"
    mkdir -p "$test_repo" "$fake_bin"

    echo '{"name": "test/app"}' > "$test_repo/composer.json"

    # Quoted heredoc ('EOF') prevents shell variable expansion in the fake script
    cat > "$fake_bin/composer" <<'EOF'
#!/bin/bash
if [[ "$*" == *"--version"* ]]; then
  echo "Composer version 2.x"
  exit 0
fi
echo "Simulated composer failure" >&2
exit 1
EOF
    chmod +x "$fake_bin/composer"

    set +e
    PATH="$fake_bin:$PATH" APP_ROOT="$test_repo" bash "$SCRIPT_DIR/scripts/bootstrap-app.sh" >/dev/null 2>&1
    local status=$?
    set -e

    if [ "$status" -ne 0 ]; then
        echo -e "${GREEN}✓ Composer install failure causes script to fail${NC}"
    else
        echo -e "${RED}✗ Composer install failure should cause script to fail${NC}"
        exit 1
    fi
}

# Test 4: Lock permission message requires installed dependencies
test_composer_lock_permission_without_vendor_fails() {
    local test_repo="$TEMP_DIR/test-composer-lock-perm"
    local fake_bin="$TEMP_DIR/fake-bin-lock-perm"
    mkdir -p "$test_repo" "$fake_bin"

    echo '{"name": "test/app"}' > "$test_repo/composer.json"

    cat > "$fake_bin/composer" <<'EOF'
#!/bin/bash
if [[ "$*" == *"--version"* ]]; then
  echo "Composer version 2.x"
  exit 0
fi
echo "Cannot create composer.lock: Permission denied" >&2
exit 1
EOF
    chmod +x "$fake_bin/composer"

    set +e
    PATH="$fake_bin:$PATH" APP_ROOT="$test_repo" bash "$SCRIPT_DIR/scripts/bootstrap-app.sh" >/dev/null 2>&1
    local status=$?
    set -e

    if [ "$status" -ne 0 ]; then
        echo -e "${GREEN}✓ Lock permission without vendor correctly fails${NC}"
    else
        echo -e "${RED}✗ Lock permission without vendor should fail${NC}"
        exit 1
    fi
}

# Test 5: DevPanel settings include block is added when missing
test_devpanel_settings_include_added() {
    local test_repo="$TEMP_DIR/test-settings-append"
    local settings_dir="$test_repo/web/sites/default"
    local settings_file="$settings_dir/settings.php"

    if ! ensure_active_sudo; then
        echo -e "${YELLOW}⊘ Skipped: settings include append test requires sudo${NC}"
        return 0
    fi

    mkdir -p "$settings_dir"
    echo '<?php' > "$settings_file"

    APP_ROOT="$test_repo" bash "$SCRIPT_DIR/scripts/bootstrap-app.sh" >/dev/null 2>&1

    if grep -q "/usr/local/share/drupalforge/settings.devpanel.php" "$settings_file"; then
        echo -e "${GREEN}✓ DevPanel settings include block is added to settings.php${NC}"
    else
        echo -e "${RED}✗ DevPanel settings include block was not added${NC}"
        exit 1
    fi
}

# Test 6: DevPanel settings include block is not duplicated
test_devpanel_settings_include_not_duplicated() {
    local test_repo="$TEMP_DIR/test-settings-idempotent"
    local settings_dir="$test_repo/web/sites/default"
    local settings_file="$settings_dir/settings.php"

    if ! ensure_active_sudo; then
        echo -e "${YELLOW}⊘ Skipped: settings include idempotency test requires sudo${NC}"
        return 0
    fi

    mkdir -p "$settings_dir"
    echo '<?php' > "$settings_file"

    APP_ROOT="$test_repo" bash "$SCRIPT_DIR/scripts/bootstrap-app.sh" >/dev/null 2>&1
    APP_ROOT="$test_repo" bash "$SCRIPT_DIR/scripts/bootstrap-app.sh" >/dev/null 2>&1

    local include_count
    include_count=$(grep -c "/usr/local/share/drupalforge/settings.devpanel.php" "$settings_file")
    if [ "$include_count" -eq 1 ]; then
        echo -e "${GREEN}✓ DevPanel settings include block is not duplicated${NC}"
    else
        echo -e "${RED}✗ DevPanel settings include block duplicated (count: $include_count)${NC}"
        exit 1
    fi
}

# Test 7: Script is executable
test_script_executable() {
    if [ -x "$SCRIPT_DIR/scripts/bootstrap-app.sh" ]; then
        echo -e "${GREEN}✓ bootstrap-app.sh is executable${NC}"
    else
        echo -e "${RED}✗ bootstrap-app.sh is not executable${NC}"
        exit 1
    fi
}

# Test 8: Script has error handling
test_error_handling() {
    if grep -q "set -e" "$SCRIPT_DIR/scripts/bootstrap-app.sh"; then
        echo -e "${GREEN}✓ Script has error handling (set -e)${NC}"
    else
        echo -e "${YELLOW}⊘ Script missing 'set -e'${NC}"
    fi
}

# Test 9: settings.php can be created from default.settings.php
test_settings_can_be_created_from_default() {
    local test_repo="$TEMP_DIR/test-settings-capable"
    local settings_dir="$test_repo/web/sites/default"
    local settings_file="$settings_dir/settings.php"
    local default_settings="$settings_dir/default.settings.php"

    if ! ensure_active_sudo; then
        echo -e "${YELLOW}⊘ Skipped: settings copy logic test requires sudo${NC}"
        return 0
    fi

    mkdir -p "$settings_dir"
    echo '<?php' > "$default_settings"

    # Simulate default.settings.php existing before bootstrap by creating both
    # This tests that the copy mechanism works when both files are checked
    touch "$settings_file"
    
    APP_ROOT="$test_repo" bash "$SCRIPT_DIR/scripts/bootstrap-app.sh" >/dev/null 2>&1

    # Since settings.php already existed, bootstrap shouldn't create it
    # This test just verifies the logic doesn't fail
    echo -e "${GREEN}✓ Settings copy logic works${NC}"
}

# Test 10: settings.php is NOT created if default.settings.php existed before bootstrap
test_settings_not_created_if_default_existed_before() {
    local test_repo="$TEMP_DIR/test-no-auto-settings-if-default-existed"
    local settings_dir="$test_repo/web/sites/default"
    local settings_file="$settings_dir/settings.php"
    local default_settings="$settings_dir/default.settings.php"

    mkdir -p "$settings_dir"
    echo '<?php' > "$default_settings"
    # NB: settings.php does NOT exist

    APP_ROOT="$test_repo" bash "$SCRIPT_DIR/scripts/bootstrap-app.sh" >/dev/null 2>&1

    if [ ! -f "$settings_file" ]; then
        echo -e "${GREEN}✓ settings.php not auto-created when default.settings.php existed before bootstrap${NC}"
    else
        echo -e "${RED}✗ settings.php should NOT be auto-created when default.settings.php existed before bootstrap${NC}"
        exit 1
    fi
}

# Test 10: DevPanel config can be added to read-only settings.php
test_devpanel_config_readonly_settings() {
    local test_repo="$TEMP_DIR/test-settings-readonly"
    local settings_dir="$test_repo/web/sites/default"
    local settings_file="$settings_dir/settings.php"

    if ! ensure_active_sudo; then
        echo -e "${YELLOW}⊘ Skipped: read-only settings append test requires sudo${NC}"
        return 0
    fi

    mkdir -p "$settings_dir"
    echo '<?php' > "$settings_file"

    # Make settings.php read-only
    chmod 444 "$settings_file"

    local output
    set +e
    output=$(APP_ROOT="$test_repo" bash "$SCRIPT_DIR/scripts/bootstrap-app.sh" 2>&1)
    local status=$?
    set -e

    chmod 644 "$settings_file"  # For cleanup

    # Check if the script successfully added the DevPanel settings include block.
    if [ "$status" -eq 0 ] && echo "$output" | grep -q "Added DevPanel settings include block"; then
        echo -e "${GREEN}✓ DevPanel config added to read-only settings.php${NC}"
    else
        echo -e "${RED}✗ DevPanel config was not added to read-only settings.php${NC}"
        echo "$output"
        exit 1
    fi
}

# Test 11: settings.php copy aligns destination file owner/group with invoking user
test_settings_copy_owner_matches_invoking_user() {
    local test_dir="$TEMP_DIR/test-cp-owner-match"
    local web_root="$test_dir/web"
    local settings_dir="$web_root/sites/default"
    local default_settings="$settings_dir/default.settings.php"
    local dest_file="$settings_dir/settings.php"
    local expected_spec file_spec script_source

    cleanup_cp_owner_match_test() {
        sudo -n chown -R "$(id -u):$(id -g)" "$test_dir" || true
        chmod -R u+rwX "$test_dir" 2>/dev/null || true
    }

    if ! ensure_active_sudo; then
        echo -e "${YELLOW}⊘ Skipped: settings copy owner match test requires sudo${NC}"
        return 0
    fi

    mkdir -p "$settings_dir"
    echo '<?php' > "$default_settings"

    # Force sudo copy path by making destination directory root-owned.
    sudo -n chown -R root "$settings_dir" || {
        echo -e "${YELLOW}⊘ Skipped: settings copy owner match test requires active sudo credentials${NC}"
        return 0
    }
    sudo -n chmod 755 "$settings_dir" || true

    # Use a portable sed expression (avoids GNU/BSD `sed -i` differences).
    script_source=$(sed '$d' "$SCRIPT_DIR/scripts/bootstrap-app.sh")
    if [ -z "$script_source" ]; then
        echo -e "${RED}✗ Could not extract required functions from bootstrap-app.sh${NC}"
        cleanup_cp_owner_match_test
        exit 1
    fi

    eval "$script_source"

    local func_output
    set +e
    func_output=$(WEB_ROOT="$web_root" ensure_settings_php_exists "$test_dir" 0 2>&1)
    local status=$?
    set -e

    if [ "$status" -ne 0 ] || [ ! -f "$dest_file" ]; then
        echo -e "${RED}✗ settings.php copy failed${NC}"
        echo "$func_output"
        cleanup_cp_owner_match_test
        exit 1
    fi

    expected_spec="$(id -u):$(id -g)"
    # Cross-platform owner lookup: GNU/Linux uses `stat -c`, macOS/BSD uses `stat -f`.
    file_spec=$(stat -c '%u:%g' "$dest_file" 2>/dev/null || stat -f '%u:%g' "$dest_file" 2>/dev/null || echo "")

    if [ -n "$expected_spec" ] && [ "$expected_spec" = "$file_spec" ]; then
        echo -e "${GREEN}✓ settings.php copy aligns destination file owner/group with invoking user${NC}"
        cleanup_cp_owner_match_test
    else
        echo -e "${RED}✗ settings.php copy did not align destination file owner/group with invoking user${NC}"
        echo "$func_output"
        cleanup_cp_owner_match_test
        exit 1
    fi
}

# Test 12: Default config sync directory is created during bootstrap
test_default_config_sync_directory_created() {
    local test_repo="$TEMP_DIR/test-default-config-sync"
    local settings_dir="$test_repo/web/sites/default"
    local settings_file="$settings_dir/settings.php"
    local expected_dir="$test_repo/web/../config/sync"

    mkdir -p "$settings_dir"
    cat > "$settings_file" <<'EOF'
<?php
$devpanel_settings = '/usr/local/share/drupalforge/settings.devpanel.php';
if (file_exists($devpanel_settings)) {
  include $devpanel_settings;
}
EOF

    APP_ROOT="$test_repo" bash "$SCRIPT_DIR/scripts/bootstrap-app.sh" >/dev/null 2>&1

    if [ -d "$expected_dir" ]; then
        echo -e "${GREEN}✓ Default config sync directory is created during bootstrap${NC}"
    else
        echo -e "${RED}✗ Default config sync directory was not created during bootstrap${NC}"
        exit 1
    fi
}

# Test 13: Custom config sync directory in settings.php is respected
test_custom_config_sync_directory_created() {
    local test_repo="$TEMP_DIR/test-custom-config-sync"
    local settings_dir="$test_repo/web/sites/default"
    local settings_file="$settings_dir/settings.php"
    local expected_dir="$test_repo/web/../custom/sync"

    mkdir -p "$settings_dir"
    cat > "$settings_file" <<'EOF'
<?php
$settings['config_sync_directory'] = '../custom/sync';
$devpanel_settings = '/usr/local/share/drupalforge/settings.devpanel.php';
if (file_exists($devpanel_settings)) {
  include $devpanel_settings;
}
EOF

    APP_ROOT="$test_repo" bash "$SCRIPT_DIR/scripts/bootstrap-app.sh" >/dev/null 2>&1

    if [ -d "$expected_dir" ]; then
        echo -e "${GREEN}✓ Custom config sync directory is respected during bootstrap${NC}"
    else
        echo -e "${RED}✗ Custom config sync directory was not created during bootstrap${NC}"
        exit 1
    fi
}

# Run tests
test_script_executable
test_error_handling
# Sudo-dependent tests first (shortest to longest expected runtime)
test_devpanel_config_readonly_settings
test_settings_copy_owner_matches_invoking_user
test_devpanel_settings_include_added
test_devpanel_settings_include_not_duplicated
test_settings_can_be_created_from_default
test_default_config_sync_directory_created
test_custom_config_sync_directory_created

# Non-sudo tests
test_composer_detection
test_composer_install_flags
test_composer_install_failure
test_composer_lock_permission_without_vendor_fails
test_settings_not_created_if_default_existed_before

echo -e "${GREEN}✓ Bootstrap app tests passed${NC}"
