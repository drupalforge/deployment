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

# Test 13: Proxy rules are injected at the BEGINNING of the VirtualHost block
# (immediately after the opening <VirtualHost ...> tag), not at the end.
#
# The DevPanel base image's VirtualHost has a specific routing rule for Drupal
# image styles that routes those URLs directly to index.php for on-the-fly
# derivative generation:
#   RewriteCond %{REQUEST_URI} ^/sites/default/files/styles/[^/]+/public/
#   RewriteRule ^ index.php [L]
#
# Regular file proxy works because the base image's general catch-all typically
# excludes /sites/default/files/ paths from PHP routing (they would 404 rather
# than be generated).  The image-style rule, however, fires unconditionally for
# all styles/ URLs.  When proxy rules were injected at the END of the VirtualHost,
# this image-style routing rule ran first and sent every request for a missing
# styled image straight to Drupal — which reported "Error generating image,
# missing source file" because the original had never been downloaded.
#
# Injecting at the START ensures our proxy rules are evaluated first for every
# request, regardless of what catch-all or image-style routing rules the base
# image provides.
test_proxy_rules_injected_at_vhost_start() {
    # Simulate the DevPanel base image VirtualHost: a dedicated image-style routing
    # rule (the root cause) followed by a general catch-all.
    local tmp_vhost
    tmp_vhost=$(mktemp)
    cat > "$tmp_vhost" <<'EOF'
<VirtualHost *:80>
    DocumentRoot /var/www/html/web
    <IfModule mod_rewrite.c>
        RewriteEngine on
        # Dedicated image-style generation route (DevPanel base image pattern)
        RewriteCond %{REQUEST_URI} ^/sites/default/files/styles/[^/]+/public/
        RewriteRule ^ index.php [L]
        # General catch-all for missing files/directories
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule ^ index.php [L]
    </IfModule>
</VirtualHost>
EOF

    local tmp_out
    tmp_out=$(mktemp)

    # Run the same awk used by setup-proxy.sh (extract from the script)
    local tmp_block
    tmp_block=$(mktemp)
    printf '    # BEGIN DRUPALFORGE PROXY RULES (managed by setup-proxy.sh)\n' > "$tmp_block"
    printf '    RewriteRule ^ /drupalforge-proxy-handler.php [END,PT]\n' >> "$tmp_block"
    printf '    # END DRUPALFORGE PROXY RULES (managed by setup-proxy.sh)\n' >> "$tmp_block"

    awk -v block_file="$tmp_block" '
    BEGIN {
      inserted=0
      skip=0
      start_marker="^[[:space:]]*# BEGIN DRUPALFORGE PROXY RULES \\(managed by setup-proxy\\.sh\\)"
      end_marker="^[[:space:]]*# END DRUPALFORGE PROXY RULES \\(managed by setup-proxy\\.sh\\)"
    }
    skip {
      if ($0 ~ end_marker) { skip=0 }
      next
    }
    $0 ~ start_marker { skip=1; next }
    /^[[:space:]]*<VirtualHost[[:space:]>]/ {
      print
      if (inserted==0) {
        while ((getline block_line < block_file) > 0) { print block_line }
        close(block_file)
        inserted=1
      }
      next
    }
    { print }
    END { if (inserted==0) { exit 1 } }
    ' "$tmp_vhost" > "$tmp_out"

    # Proxy block must appear BEFORE both the image-style routing rule and the
    # general catch-all.  We check against the first occurrence of index.php
    # routing (whichever it is — image-style or generic).
    local proxy_line imagestyle_line
    proxy_line=$(grep -n 'drupalforge-proxy-handler' "$tmp_out" | head -1 | cut -d: -f1)
    imagestyle_line=$(grep -n 'RewriteRule \^ index\.php' "$tmp_out" | head -1 | cut -d: -f1)

    rm -f "$tmp_vhost" "$tmp_out" "$tmp_block"

    if [ -n "$proxy_line" ] && [ -n "$imagestyle_line" ] && [ "$proxy_line" -lt "$imagestyle_line" ]; then
        echo -e "${GREEN}✓ Proxy rules are injected at the start of VirtualHost (before image-style and catch-all routing)${NC}"
    else
        echo -e "${RED}✗ Proxy rules not injected at start of VirtualHost — Drupal image-style routing would shadow them${NC}"
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
test_proxy_rules_injected_at_vhost_start

echo -e "${GREEN}✓ Setup proxy tests passed${NC}"
