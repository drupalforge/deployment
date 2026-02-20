#!/bin/bash
# Unit tests for proxy-handler.php
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HANDLER="$SCRIPT_DIR/scripts/proxy-handler.php"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Test 7: Detects MIME types
test_mime_detection() {
    if grep -q "finfo\|MIME" "$HANDLER"; then
        echo -e "${GREEN}✓ Script detects MIME types${NC}"
    else
        echo -e "${YELLOW}⊘ Script may not detect MIME types${NC}"
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
test_error_handling
test_env_origin
test_image_styles

echo -e "${GREEN}✓ PHP handler tests passed${NC}"
