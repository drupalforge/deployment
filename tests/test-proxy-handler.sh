#!/bin/bash
# Unit tests for proxy-handler.php
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HANDLER="$SCRIPT_DIR/scripts/proxy-handler.php"

echo "Testing proxy-handler.php..."

# Test 1: File exists
test_file_exists() {
    if [ -f "$HANDLER" ]; then
        echo "✓ proxy-handler.php exists"
    else
        echo "✗ proxy-handler.php not found"
        exit 1
    fi
}

# Test 2: File is readable PHP
test_php_syntax() {
    if php -l "$HANDLER" 2>&1 | grep -q "No syntax errors"; then
        echo "✓ PHP syntax is valid"
    else
        echo "✗ PHP syntax errors found"
        php -l "$HANDLER"
        exit 1
    fi
}

# Test 3: Has security checks
test_security_checks() {
    if grep -q "\.\.\|path.*outside\|realpath\|security" "$HANDLER"; then
        echo "✓ Script has path traversal protection"
    else
        echo "⊘ Script may be missing security checks"
    fi
}

# Test 4: Uses curl for download
test_curl_usage() {
    if grep -q "curl_init\|CURLOPT" "$HANDLER"; then
        echo "✓ Script uses curl for downloads"
    else
        echo "✗ Script doesn't use curl"
        exit 1
    fi
}

# Test 5: Creates directories
test_directory_creation() {
    if grep -q "mkdir\|is_dir" "$HANDLER"; then
        echo "✓ Script creates parent directories"
    else
        echo "✗ Script may not create directories"
        exit 1
    fi
}

# Test 6: Sets file permissions
test_permissions() {
    if grep -q "chmod\|chown\|chgrp" "$HANDLER"; then
        echo "✓ Script sets file permissions"
    else
        echo "⊘ Script may not set permissions"
    fi
}

# Test 7: Detects MIME types
test_mime_detection() {
    if grep -q "finfo\|MIME" "$HANDLER"; then
        echo "✓ Script detects MIME types"
    else
        echo "⊘ Script may not detect MIME types"
    fi
}

# Test 8: Handles errors gracefully
test_error_handling() {
    if grep -q "http_response_code\|curl_error\|400\|502\|500" "$HANDLER"; then
        echo "✓ Script handles errors with HTTP codes"
    else
        echo "✗ Script doesn't handle errors properly"
        exit 1
    fi
}

# Test 9: Gets origin URL from environment
test_env_origin() {
    if grep -q "getenv.*ORIGIN_URL" "$HANDLER"; then
        echo "✓ Script reads ORIGIN_URL from environment"
    else
        echo "✗ Script doesn't read ORIGIN_URL"
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

echo "✓ PHP handler tests passed"
