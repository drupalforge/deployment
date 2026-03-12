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
    # Shared file-existence bypass and per-path handler routing (detailed per-path structure validated in test_inline_rewrite_awk and test_image_style_proxied_when_original_missing)
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

# Test 10: Script injects rewrite rules into both the live vhost config and the DevPanel template
test_vhost_rewrite_scope() {
    if grep -q '/etc/apache2/sites-enabled/000-default.conf' "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
       grep -q '/templates/000-default.conf' "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
       grep -q 'BEGIN DRUPALFORGE PROXY RULES' "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo -e "${GREEN}✓ Script injects managed rewrite rules into both live vhost and DevPanel template${NC}"
    else
        echo -e "${RED}✗ Script does not inject rewrite rules into both vhost targets${NC}"
        exit 1
    fi
}

# Test 11: Image style rule uses a POSITIVE (non-negated) match so %1 is correctly set;
# the regular-file rule excludes the styles/ subtree so existing originals fall through to Drupal.
test_image_style_proxied_when_original_missing() {
    # Image style rule: positive match captures the original subpath into %1
    if grep -q 'RewriteCond %%{REQUEST_URI} \^.*styles.*/public/' "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
       grep -q 'RewriteCond %%{DOCUMENT_ROOT}.*%%1 !-f' "$SCRIPT_DIR/scripts/setup-proxy.sh" && \
       grep -q 'RewriteCond %%{REQUEST_URI} !.*styles/' "$SCRIPT_DIR/scripts/setup-proxy.sh"; then
        echo -e "${GREEN}✓ Image style rule uses positive match (%1 set correctly); regular-file rule excludes styles/ subtree${NC}"
    else
        echo -e "${RED}✗ Per-path rule structure incorrect — image style or regular-file rule missing${NC}"
        exit 1
    fi
}

# Test 12: Image style Apache RewriteCond regex handles query strings.
# Extracts the regex format string from setup-proxy.sh, substitutes a real path prefix,
# and tests the resulting pattern against a REQUEST_URI.
test_image_style_apache_regex() {
    # Extract the regex portion from the image-style RewriteCond printf line.
    # The line in setup-proxy.sh is:
    #   printf '        RewriteCond %%{REQUEST_URI} ^%s/styles/[^/]+/public/([^?]+)\n' "$path"
    # After stripping everything up to "REQUEST_URI} " and trimming the trailing \n...:
    #   ^%s/styles/[^/]+/public/([^?]+)
    local pattern_fmt
    pattern_fmt=$(grep 'RewriteCond.*styles.*public' "$SCRIPT_DIR/scripts/setup-proxy.sh" \
        | sed 's/.*REQUEST_URI} //; s/\\n.*//' \
        | head -1)
    if [ -z "$pattern_fmt" ]; then
        echo -e "${RED}✗ Image style RewriteCond not found in setup-proxy.sh${NC}"
        exit 1
    fi

    # Substitute a real path prefix for the %s placeholder to get the concrete Apache pattern.
    local pattern="${pattern_fmt/\%s/\/sites\/default\/files}"

    # Test with the exact REQUEST_URI from the original bug report.
    local test_uri="/sites/default/files/styles/medium/public/2026-02/josh-carter-5kk7fGDdGFM-unsplash.jpg?itok=SUwEM6-9"
    if [[ ! "$test_uri" =~ $pattern ]]; then
        echo -e "${RED}✗ Image style RewriteCond does not match REQUEST_URI with query string${NC}"
        echo -e "${RED}  Pattern: $pattern${NC}"
        echo -e "${RED}  URI:     $test_uri${NC}"
        exit 1
    fi

    local captured="${BASH_REMATCH[1]}"
    if [[ "$captured" == *"?"* ]]; then
        echo -e "${RED}✗ Image style RewriteCond capture group includes query string: $captured${NC}"
        exit 1
    fi
    if [[ "$captured" != "2026-02/josh-carter-5kk7fGDdGFM-unsplash.jpg" ]]; then
        echo -e "${RED}✗ Image style RewriteCond captured wrong path: $captured${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Image style RewriteCond matches REQUEST_URI with query string; capture group: $captured${NC}"
}


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
test_image_style_apache_regex

echo -e "${GREEN}✓ Setup proxy tests passed${NC}"
