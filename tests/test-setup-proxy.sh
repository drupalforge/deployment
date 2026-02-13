#!/bin/bash
# Unit tests for setup-proxy.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Testing setup-proxy.sh..."

# Test 1: Script is executable
test_script_executable() {
    if [ -x "$SCRIPT_DIR/scripts/setup-proxy.sh" ]; then
        echo "✓ setup-proxy.sh is executable"
    else
        echo "✗ setup-proxy.sh is not executable"
        exit 1
    fi
}

# Test 2: Script has error handling
test_error_handling() {
    if grep -q "set -e" "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo "✓ Script has error handling (set -e)"
    else
        echo "⊘ Script missing 'set -e'"
    fi
}

# Test 3: Stage File Proxy detection
test_stage_file_proxy_detection() {
    if grep -q "has_stage_file_proxy\|stage_file_proxy" "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo "✓ Script detects Stage File Proxy module"
    else
        echo "✗ Script doesn't detect Stage File Proxy"
        exit 1
    fi
}

# Test 4: Apache proxy fallback
test_apache_proxy_fallback() {
    if grep -q "configure_apache_proxy\|mod_rewrite\|RewriteRule" "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo "✓ Script has Apache proxy fallback"
    else
        echo "✗ Script missing Apache proxy fallback"
        exit 1
    fi
}

# Test 5: Rewrite rules generation
test_rewrite_rules() {
    if grep -q "RewriteCond\|RewriteRule" "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo "✓ Script generates rewrite rules"
    else
        echo "✗ Script doesn't generate rewrite rules"
        exit 1
    fi
}

# Test 6: Handler setup
test_handler_setup() {
    if grep -q "proxy-handler\|drupalforge-proxy-handler" "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo "✓ Script sets up PHP handler"
    else
        echo "✗ Script doesn't set up handler"
        exit 1
    fi
}

# Test 7: Environment variable handling
test_env_variables() {
    if grep -q "ORIGIN_URL\|FILE_PROXY_PATHS\|WEB_ROOT" "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo "✓ Script handles proxy environment variables"
    else
        echo "✗ Script doesn't handle env variables"
        exit 1
    fi
}

# Test 8: Default paths
test_default_paths() {
    if grep -q "sites/default/files" "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo "✓ Script has sensible defaults"
    else
        echo "⊘ Script may not have defaults"
    fi
}

# Run tests
test_script_executable
test_error_handling
test_stage_file_proxy_detection
test_apache_proxy_fallback
test_rewrite_rules
test_handler_setup
test_env_variables
test_default_paths

echo "✓ Setup proxy tests passed"
