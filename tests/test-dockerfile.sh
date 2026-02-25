#!/bin/bash
# Tests for Dockerfile configuration
#
# NOTE: These are SYNTAX/PATTERN tests that check the Dockerfile text.
# They do NOT build Docker images. Actual builds happen in CI's docker-build job.
# To test actual Docker builds locally, run:
#   docker build --build-arg PHP_VERSION=8.3 -t test-df-deployment:8.3 .
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="$SCRIPT_DIR/Dockerfile"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Testing Dockerfile...${NC}"

# Test 1: Dockerfile exists
test_dockerfile_exists() {
    if [ -f "$DOCKERFILE" ]; then
        echo -e "${GREEN}✓ Dockerfile exists${NC}"
    else
        echo -e "${RED}✗ Dockerfile not found${NC}"
        exit 1
    fi
}

# Test 2: Extends devpanel/php base
test_base_image() {
    if grep -q "FROM devpanel/php" "$DOCKERFILE"; then
        echo -e "${GREEN}✓ Extends devpanel/php base image${NC}"
    else
        echo -e "${RED}✗ Doesn't extend devpanel/php${NC}"
        exit 1
    fi
}

# Test 3: PHP version argument
test_php_version_arg() {
    if grep -q "ARG PHP_VERSION" "$DOCKERFILE"; then
        echo -e "${GREEN}✓ Supports PHP_VERSION build argument${NC}"
    else
        echo -e "${RED}✗ Missing PHP_VERSION argument${NC}"
        exit 1
    fi
}

# Test 4: Copies all required scripts
test_script_copies() {
    local scripts=("bootstrap-app" "import-database" "setup-proxy" "deployment-entrypoint")
    for script in "${scripts[@]}"; do
        if grep -q "COPY.*$script" "$DOCKERFILE"; then
            echo -e "${GREEN}✓ Copies $script${NC}"
        else
            echo -e "${RED}✗ Missing $script copy${NC}"
            exit 1
        fi
    done
}

# Test 5: Copies PHP handler
test_php_handler_copy() {
    if grep -q "COPY.*proxy-handler.php" "$DOCKERFILE"; then
        echo -e "${GREEN}✓ Copies PHP proxy handler${NC}"
    else
        echo -e "${RED}✗ Missing proxy-handler.php copy${NC}"
        exit 1
    fi
}

# Test 6: Copies Apache config
test_apache_config_copy() {
    if grep -q "COPY.*apache-proxy.conf" "$DOCKERFILE"; then
        echo -e "${GREEN}✓ Copies Apache proxy config${NC}"
    else
        echo -e "${RED}✗ Missing apache-proxy.conf copy${NC}"
        exit 1
    fi
}

# Test 7: Copies DevPanel settings config
test_devpanel_settings_copy() {
    if grep -q "COPY.*settings.devpanel.php" "$DOCKERFILE"; then
        echo -e "${GREEN}✓ Copies DevPanel settings config${NC}"
    else
        echo -e "${RED}✗ Missing settings.devpanel.php copy${NC}"
        exit 1
    fi
}

# Test 8: Scripts are copied (execute permissions preserved from source)
test_scripts_copied() {
    # The scripts in the scripts/ directory already have execute permissions
    # which are preserved when copied to the image via COPY command
    local scripts_dir="$SCRIPT_DIR/scripts"
    if [ -x "$scripts_dir/bootstrap-app.sh" ] && [ -x "$scripts_dir/deployment-entrypoint.sh" ]; then
        echo -e "${GREEN}✓ Scripts have execute permissions in source${NC}"
    else
        echo -e "${RED}✗ Scripts missing execute permissions in source${NC}"
        exit 1
    fi
}

# Test 9: Enables required Apache modules
test_apache_modules() {
    local modules=("rewrite" "proxy" "proxy_http")
    for module in "${modules[@]}"; do
        if grep -q "a2enmod.*$module" "$DOCKERFILE"; then
            echo -e "${GREEN}✓ Enables mod_$module${NC}"
        else
            echo -e "${RED}✗ Doesn't enable mod_$module${NC}"
            exit 1
        fi
    done
}

# Test 10: Sets ENTRYPOINT
test_entrypoint() {
    if grep -q "ENTRYPOINT.*deployment-entrypoint" "$DOCKERFILE"; then
        echo -e "${GREEN}✓ Sets deployment entrypoint${NC}"
    else
        echo -e "${RED}✗ Missing ENTRYPOINT${NC}"
        exit 1
    fi
}

# Test 11: Installs AWS CLI via bundled installer
test_aws_cli_install() {
    if grep -q "awscli-exe-linux" "$DOCKERFILE"; then
        echo -e "${GREEN}✓ Installs AWS CLI via bundled installer${NC}"
    else
        echo -e "${RED}✗ Missing AWS CLI bundled installer configuration${NC}"
        exit 1
    fi
}

# Test 12: Has labels
test_labels() {
    if grep -q "LABEL.*org.opencontainers.image" "$DOCKERFILE"; then
        echo -e "${GREEN}✓ Has OCI labels${NC}"
    else
        echo -e "${YELLOW}⊘ Missing OCI labels${NC}"
    fi
}

# Run tests
test_dockerfile_exists
test_base_image
test_php_version_arg
test_script_copies
test_php_handler_copy
test_apache_config_copy
test_devpanel_settings_copy
test_scripts_copied
test_apache_modules
test_entrypoint
test_aws_cli_install
test_labels

echo -e "${GREEN}✓ Dockerfile tests passed${NC}"
