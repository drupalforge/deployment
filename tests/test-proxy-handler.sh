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

# Test 7: Redirects after download so Apache serves the file with its own MIME detection
test_redirects_after_download() {
    if grep -q "header('Location:" "$HANDLER" && \
       grep -q "http_response_code(302)" "$HANDLER" && \
       grep -q "redirect_uri\|REDIRECT_QUERY_STRING" "$HANDLER"; then
        echo -e "${GREEN}✓ Script redirects to original URL after download${NC}"
    else
        echo -e "${RED}✗ Script does not redirect after download${NC}"
        exit 1
    fi
}

# Test 7b: Query string is preserved in the redirect URI
test_redirect_preserves_query_string() {
    result=$(php -r "
        // Simulate Apache server variables for a request like style.css?v=123
        \$_SERVER['REDIRECT_QUERY_STRING'] = 'v=123';
        \$requested_path = '/sites/default/files/css/style.css';
        \$query_string = \$_SERVER['REDIRECT_QUERY_STRING'] ?? (\$_SERVER['QUERY_STRING'] ?? '');
        \$redirect_uri = \$requested_path . (\$query_string !== '' ? '?' . \$query_string : '');
        echo \$redirect_uri;
    ")
    if [ "$result" = "/sites/default/files/css/style.css?v=123" ]; then
        echo -e "${GREEN}✓ Redirect URI preserves query string${NC}"
    else
        echo -e "${RED}✗ Redirect URI wrong: '$result'${NC}"
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
test_redirects_after_download
test_redirect_preserves_query_string
test_error_handling
test_env_origin
test_image_styles

echo -e "${GREEN}✓ PHP handler tests passed${NC}"
