#!/bin/bash
# Tests for Dockerfile configuration
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="$SCRIPT_DIR/Dockerfile"

echo "Testing Dockerfile..."

# Test 1: Dockerfile exists
test_dockerfile_exists() {
    if [ -f "$DOCKERFILE" ]; then
        echo "✓ Dockerfile exists"
    else
        echo "✗ Dockerfile not found"
        exit 1
    fi
}

# Test 2: Extends devpanel/php base
test_base_image() {
    if grep -q "FROM devpanel/php" "$DOCKERFILE"; then
        echo "✓ Extends devpanel/php base image"
    else
        echo "✗ Doesn't extend devpanel/php"
        exit 1
    fi
}

# Test 3: PHP version argument
test_php_version_arg() {
    if grep -q "ARG PHP_VERSION" "$DOCKERFILE"; then
        echo "✓ Supports PHP_VERSION build argument"
    else
        echo "✗ Missing PHP_VERSION argument"
        exit 1
    fi
}

# Test 4: Copies all required scripts
test_script_copies() {
    local scripts=("bootstrap-app" "import-database" "setup-proxy" "deployment-entrypoint")
    for script in "${scripts[@]}"; do
        if grep -q "COPY.*$script" "$DOCKERFILE"; then
            echo "✓ Copies $script"
        else
            echo "✗ Missing $script copy"
            exit 1
        fi
    done
}

# Test 5: Copies PHP handler
test_php_handler_copy() {
    if grep -q "COPY.*proxy-handler.php" "$DOCKERFILE"; then
        echo "✓ Copies PHP proxy handler"
    else
        echo "✗ Missing proxy-handler.php copy"
        exit 1
    fi
}

# Test 6: Copies Apache config
test_apache_config_copy() {
    if grep -q "COPY.*apache-proxy.conf" "$DOCKERFILE"; then
        echo "✓ Copies Apache proxy config"
    else
        echo "✗ Missing apache-proxy.conf copy"
        exit 1
    fi
}

# Test 7: Scripts are copied (execute permissions preserved from source)
test_scripts_copied() {
    # The scripts in the scripts/ directory already have execute permissions
    # which are preserved when copied to the image via COPY command
    local scripts_dir="$SCRIPT_DIR/scripts"
    if [ -x "$scripts_dir/bootstrap-app.sh" ] && [ -x "$scripts_dir/deployment-entrypoint.sh" ]; then
        echo "✓ Scripts have execute permissions in source"
    else
        echo "✗ Scripts missing execute permissions in source"
        exit 1
    fi
}

# Test 8: Enables required Apache modules
test_apache_modules() {
    local modules=("rewrite" "proxy" "proxy_http")
    for module in "${modules[@]}"; do
        if grep -q "a2enmod.*$module" "$DOCKERFILE"; then
            echo "✓ Enables mod_$module"
        else
            echo "✗ Doesn't enable mod_$module"
            exit 1
        fi
    done
}

# Test 9: Sets ENTRYPOINT
test_entrypoint() {
    if grep -q "ENTRYPOINT.*deployment-entrypoint" "$DOCKERFILE"; then
        echo "✓ Sets deployment entrypoint"
    else
        echo "✗ Missing ENTRYPOINT"
        exit 1
    fi
}

# Test 10: Has labels
test_labels() {
    if grep -q "LABEL.*org.opencontainers.image" "$DOCKERFILE"; then
        echo "✓ Has OCI labels"
    else
        echo "⊘ Missing OCI labels"
    fi
}

# Run tests
test_dockerfile_exists
test_base_image
test_php_version_arg
test_script_copies
test_php_handler_copy
test_apache_config_copy
test_scripts_copied
test_apache_modules
test_entrypoint
test_labels

echo "✓ Dockerfile tests passed"
