#!/bin/bash
# Unit tests for setup-proxy.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Testing setup-proxy.sh...${NC}"

# Test 1: Script is executable
test_script_executable() {
    if [ -x "$SCRIPT_DIR/scripts/setup-proxy.sh" ]; then
        echo -e "${GREEN}✓ setup-proxy.sh is executable${NC}"
    else
        echo -e "${RED}✗ setup-proxy.sh is not executable${NC}"
        exit 1
    fi
}

# Test 2: Script has error handling
test_error_handling() {
    if grep -q "set -e" "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo -e "${GREEN}✓ Script has error handling (set -e)${NC}"
    else
        echo -e "${YELLOW}⊘ Script missing 'set -e'${NC}"
    fi
}

# Test 3: Stage File Proxy detection
test_stage_file_proxy_detection() {
    if grep -q "has_stage_file_proxy\|stage_file_proxy" "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo -e "${GREEN}✓ Script detects Stage File Proxy module${NC}"
    else
        echo -e "${RED}✗ Script doesn't detect Stage File Proxy${NC}"
        exit 1
    fi
}

# Test 4: Apache proxy fallback
test_apache_proxy_fallback() {
    if grep -q "configure_apache_proxy\|mod_rewrite\|RewriteRule" "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo -e "${GREEN}✓ Script has Apache proxy fallback${NC}"
    else
        echo -e "${RED}✗ Script missing Apache proxy fallback${NC}"
        exit 1
    fi
}

# Test 5: Rewrite rules generation
test_rewrite_rules() {
    if grep -q "%{REQUEST_FILENAME} -f" "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
       grep -q "%{REQUEST_FILENAME} -d" "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
       grep -q '/drupalforge-proxy-handler.php \[END\]' "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo -e "${GREEN}✓ Script generates rewrite rules${NC}"
    else
        echo -e "${RED}✗ Script doesn't generate rewrite rules${NC}"
        exit 1
    fi
}

# Test 6: Handler setup
test_handler_setup() {
    if grep -q "proxy-handler\|drupalforge-proxy-handler" "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo -e "${GREEN}✓ Script sets up PHP handler${NC}"
    else
        echo -e "${RED}✗ Script doesn't set up handler${NC}"
        exit 1
    fi
}

# Test 7: Environment variable handling
test_env_variables() {
    if grep -q "ORIGIN_URL\|FILE_PROXY_PATHS\|WEB_ROOT" "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo -e "${GREEN}✓ Script handles proxy environment variables${NC}"
    else
        echo -e "${RED}✗ Script doesn't handle env variables${NC}"
        exit 1
    fi
}

# Test 8: Default paths
test_default_paths() {
    if grep -q "sites/default/files" "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo -e "${GREEN}✓ Script has sensible defaults${NC}"
    else
        echo -e "${YELLOW}⊘ Script may not have defaults${NC}"
    fi
}

# Test 9: Unified helper performs rewrite lifecycle operations
test_unified_rewrite_helper() {
    if grep -q "update_proxy_rewrite_rules()" "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
       grep -q "drupalforge-proxy-handler" "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
    grep -q "REQUEST_FILENAME" "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
       grep -q "RewriteCond %%{REQUEST_URI}" "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo -e "${GREEN}✓ Unified helper manages cleanup, bypass, and injection${NC}"
    else
        echo -e "${RED}✗ Unified helper lifecycle behavior not found${NC}"
        exit 1
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
test_unified_rewrite_helper

echo -e "${GREEN}✓ Setup proxy tests passed${NC}"
