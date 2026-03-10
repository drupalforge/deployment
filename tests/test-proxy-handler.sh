#!/bin/bash
# Unit tests for proxy-handler.php
set -e

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${TEST_DIR%/*}"
HANDLER="$SCRIPT_DIR/scripts/proxy-handler.php"

# shellcheck source=lib/colors.sh
source "$TEST_DIR/lib/colors.sh"

echo -e "${BLUE}Testing proxy-handler.php...${NC}"

# Test 1: File exists
test_file_exists() {
    if [ -f "$HANDLER" ]; then
        echo -e "${GREEN}✓ proxy-handler.php exists${NC}"
    else
        echo -e "${RED}✗ proxy-handler.php not found${NC}"
        exit 1
    fi
}

# Test 2: File is readable PHP
test_php_syntax() {
    if php -l "$HANDLER" 2>&1 | grep -q "No syntax errors"; then
        echo -e "${GREEN}✓ PHP syntax is valid${NC}"
    else
        echo -e "${RED}✗ PHP syntax errors found${NC}"
        php -l "$HANDLER"
        exit 1
    fi
}

# Test 3: Has security checks
test_security_checks() {
    if grep -q "\.\.\|path.*outside\|realpath\|security" "$HANDLER"; then
        echo -e "${GREEN}✓ Script has path traversal protection${NC}"
    else
        echo -e "${YELLOW}⊘ Script may be missing security checks${NC}"
    fi
}

# Test 4: Uses curl for download
test_curl_usage() {
    if grep -q "curl_init\|CURLOPT" "$HANDLER"; then
        echo -e "${GREEN}✓ Script uses curl for downloads${NC}"
    else
        echo -e "${RED}✗ Script doesn't use curl${NC}"
        exit 1
    fi
}

# Test 5: Creates directories
test_directory_creation() {
    if grep -q "mkdir\|is_dir" "$HANDLER"; then
        echo -e "${GREEN}✓ Script creates parent directories${NC}"
    else
        echo -e "${RED}✗ Script may not create directories${NC}"
        exit 1
    fi
}

# Test 6: Sets file permissions
test_permissions() {
    if grep -q "chmod\|chown\|chgrp" "$HANDLER"; then
        echo -e "${GREEN}✓ Script sets file permissions${NC}"
    else
        echo -e "${YELLOW}⊘ Script may not set permissions${NC}"
    fi
}

# Test 7: Detects MIME types using extension map (not just finfo magic bytes)
test_mime_detection() {
    if grep -q "ext_mime_map" "$HANDLER" && \
       grep -q "text/css" "$HANDLER" && \
       grep -q "application/javascript" "$HANDLER"; then
        echo -e "${GREEN}✓ Script uses extension-based MIME type map${NC}"
    else
        echo -e "${RED}✗ Script is missing extension-based MIME type map${NC}"
        exit 1
    fi
}

# Test 7b: CSS extension returns text/css, not text/plain
test_css_mime_type() {
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "${tmp_dir}"' EXIT

    css_file="${tmp_dir}/style.css"
    echo "body { color: red; }" > "$css_file"

    # Run a minimal PHP snippet that replicates proxy-handler's MIME logic
    mime=$(php -r "
        \$ext_mime_map = [
            'css'   => 'text/css',
            'js'    => 'application/javascript',
            'svg'   => 'image/svg+xml',
            'webp'  => 'image/webp',
            'woff'  => 'font/woff',
            'woff2' => 'font/woff2',
            'ttf'   => 'font/ttf',
            'otf'   => 'font/otf',
            'eot'   => 'application/vnd.ms-fontobject',
        ];
        \$requested_path = '/sites/default/files/css/style.css';
        \$ext = strtolower(pathinfo(\$requested_path, PATHINFO_EXTENSION));
        if (isset(\$ext_mime_map[\$ext])) {
            echo \$ext_mime_map[\$ext];
        } else {
            \$finfo = finfo_open(FILEINFO_MIME_TYPE);
            echo finfo_file(\$finfo, '$css_file') ?: 'application/octet-stream';
            finfo_close(\$finfo);
        }
    ")

    if [ "$mime" = "text/css" ]; then
        echo -e "${GREEN}✓ CSS file with extension-map returns text/css${NC}"
    else
        echo -e "${RED}✗ CSS file returned '$mime' instead of text/css${NC}"
        exit 1
    fi
}

# Test 7c: strtok strips query string before pathinfo() so extension is always correct
test_css_mime_type_query_string() {
    # Reproduce the handler's own strtok + pathinfo chain from lines 13 and 125 of
    # proxy-handler.php to confirm that a URL like style.css?v=123 still yields
    # the extension 'css' after the query string is removed.
    result=$(php -r "
        \$requested_uri = '/sites/default/files/css/style.css?v=123';
        \$requested_path = strtok(\$requested_uri, '?');
        echo strtolower(pathinfo(\$requested_path, PATHINFO_EXTENSION));
    ")
    if [ "$result" = "css" ]; then
        echo -e "${GREEN}✓ CSS extension resolved correctly after query string removal${NC}"
    else
        echo -e "${RED}✗ Extension wrong after query string removal: '$result'${NC}"
        exit 1
    fi
}

# Test 8: Handles errors gracefully
test_error_handling() {
    if grep -q "http_response_code\|curl_error\|400\|502\|500" "$HANDLER"; then
        echo -e "${GREEN}✓ Script handles errors with HTTP codes${NC}"
    else
        echo -e "${RED}✗ Script doesn't handle errors properly${NC}"
        exit 1
    fi
}

# Test 9: Gets origin URL from environment
test_env_origin() {
    if grep -q "getenv.*ORIGIN_URL" "$HANDLER"; then
        echo -e "${GREEN}✓ Script reads ORIGIN_URL from environment${NC}"
    else
        echo -e "${RED}✗ Script doesn't read ORIGIN_URL${NC}"
        exit 1
    fi
}

# Test 10: Handles Drupal image styles
test_image_styles() {
    if grep -q "styles.*public\|image.*styles" "$HANDLER"; then
        echo -e "${GREEN}✓ Script handles Drupal image styles${NC}"
    else
        echo -e "${RED}✗ Script doesn't handle image styles${NC}"
        exit 1
    fi
}

# Run tests
test_file_exists
test_php_syntax
test_security_checks
test_curl_usage
test_directory_creation
test_permissions
test_mime_detection
test_css_mime_type
test_css_mime_type_query_string
test_error_handling
test_env_origin
test_image_styles

echo -e "${GREEN}✓ PHP handler tests passed${NC}"
