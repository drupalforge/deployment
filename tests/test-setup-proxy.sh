#!/bin/bash
# Unit tests for setup-proxy.sh
set -e

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${TEST_DIR%/*}"

# shellcheck source=lib/colors.sh
source "$TEST_DIR/lib/colors.sh"

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
    # Shared file-existence bypass and per-path handler routing (full per-path structure in tests 9/11)
    if grep -q 'RewriteCond %%{DOCUMENT_ROOT}%%{REQUEST_URI} -f \[OR\]' "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
        grep -q 'RewriteCond %%{DOCUMENT_ROOT}%%{REQUEST_URI} -d' "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
        grep -q 'RewriteRule \^ - \[L\]' "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
        grep -q 'RewriteCond %%{DOCUMENT_ROOT}.*%%1 !-f' "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
        grep -q 'drupalforge-proxy-handler\.php.*\[END,PT\]' "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo -e "${GREEN}✓ Script generates rewrite rules with shared file-existence bypass and handler routing${NC}"
    else
        echo -e "${RED}✗ Script doesn't generate rewrite rules with bypass and handler routing${NC}"
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

# Test 9: Two separate per-path rules — image style uses positive match; regular files exclude styles/
test_inline_rewrite_awk() {
    if grep -q "drupalforge-proxy-handler" "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
       grep -q "RewriteCond %%{REQUEST_URI}" "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
       grep -q "\[END,PT\]" "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
       grep -q "# Image style proxy:" "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
       grep -q "# File proxy:" "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
       grep -q "BEGIN DRUPALFORGE PROXY RULES" "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo -e "${GREEN}✓ Script generates two per-path rules: image style proxy and regular file proxy${NC}"
    else
        echo -e "${RED}✗ Two per-path rule structure not found${NC}"
        exit 1
    fi
}

# Test 10: Script targets vhost-scoped rewrite injection for live requests
test_vhost_rewrite_scope() {
    if grep -q '/templates/000-default.conf\|/etc/apache2/sites-available/000-default.conf' "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
       grep -q 'BEGIN DRUPALFORGE PROXY RULES' "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo -e "${GREEN}✓ Script injects managed rewrite rules into active vhost scope${NC}"
    else
        echo -e "${RED}✗ Script does not manage vhost-scoped rewrite injection${NC}"
        exit 1
    fi
}

# Test 11: Image style rule uses a POSITIVE (non-negated) match so %1 is correctly set;
# the regular-file rule excludes the styles/ subtree so existing originals fall through to Drupal.
test_image_style_proxied_when_original_missing() {
    # Image style rule: positive match captures the original subpath into %1
    if grep -q 'RewriteCond %%{REQUEST_URI} \^.*styles.*/public/(.+)' "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
       grep -q 'RewriteCond %%{DOCUMENT_ROOT}.*%%1 !-f' "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
       grep -q 'RewriteCond %%{REQUEST_URI} !.*styles/' "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo -e "${GREEN}✓ Image style rule uses positive match (%1 set correctly); regular-file rule excludes styles/ subtree${NC}"
    else
        echo -e "${RED}✗ Per-path rule structure incorrect — image style or regular-file rule missing${NC}"
        exit 1
    fi
}

# Test 12: SetEnv directives are written into the injected vhost block so that
# ORIGIN_URL and WEB_ROOT are available to proxy-handler.php at request time.
# PHP running under Apache does not inherit shell environment variables; without
# these SetEnv lines the handler returns 503 on every request.
test_setenv_in_vhost_block() {
    if grep -q 'SetEnv ORIGIN_URL' "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
       grep -q 'SetEnv WEB_ROOT' "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo -e "${GREEN}✓ Script writes SetEnv ORIGIN_URL and WEB_ROOT into injected vhost block${NC}"
    else
        echo -e "${RED}✗ SetEnv ORIGIN_URL / WEB_ROOT not found — handler will return 503 at runtime${NC}"
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
test_inline_rewrite_awk
test_vhost_rewrite_scope
test_image_style_proxied_when_original_missing
test_setenv_in_vhost_block

echo -e "${GREEN}✓ Setup proxy tests passed${NC}"
