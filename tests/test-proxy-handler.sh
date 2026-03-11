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
       grep -q "true, 302" "$HANDLER" && \
       grep -q "redirect_uri\|REDIRECT_QUERY_STRING" "$HANDLER"; then
        echo -e "${GREEN}✓ Script redirects to original URL after download${NC}"
    else
        echo -e "${RED}✗ Script does not redirect after download${NC}"
        exit 1
    fi
}

# Test 8: Query string is preserved in the redirect URI
# Grep the handler itself to confirm it reconstructs original request metadata
# from Apache redirect/server vars and preserves the query string in redirect URI.
test_redirect_preserves_query_string() {
    if grep -q "REDIRECT_URL" "$HANDLER" && \
       grep -q "REDIRECT_QUERY_STRING" "$HANDLER" && \
       grep -q "redirect_uri.*query_string" "$HANDLER"; then
        echo -e "${GREEN}✓ Redirect URI preserves query string from Apache rewrite/server metadata${NC}"
    else
        echo -e "${RED}✗ Redirect URI does not preserve query string or original request metadata is missing${NC}"
        exit 1
    fi
}

# Test 9: Handles errors gracefully
test_error_handling() {
    if grep -q "http_response_code\|curl_error\|400\|502\|500" "$HANDLER"; then
        echo -e "${GREEN}✓ Script handles errors with HTTP codes${NC}"
    else
        echo -e "${RED}✗ Script doesn't handle errors properly${NC}"
        exit 1
    fi
}

# Test 10: Gets origin URL from environment
test_env_origin() {
    if grep -q "getenv.*ORIGIN_URL" "$HANDLER"; then
        echo -e "${GREEN}✓ Script reads ORIGIN_URL from environment${NC}"
    else
        echo -e "${RED}✗ Script doesn't read ORIGIN_URL${NC}"
        exit 1
    fi
}

# Test 11: Handles Drupal image styles
test_image_styles() {
    if grep -q "styles.*public\|image.*styles" "$HANDLER"; then
        echo -e "${GREEN}✓ Script handles Drupal image styles${NC}"
    else
        echo -e "${RED}✗ Script doesn't handle image styles${NC}"
        exit 1
    fi
}

# Test 12: Image style path regex correctly maps a styled image URL to the original path.
# Extracts the regex from the handler at test time so the test stays in sync with
# any future changes to the pattern.
test_image_style_regex() {
    if ! command -v php > /dev/null 2>&1; then
        echo -e "${YELLOW}⊘ Skipped: image style regex test requires PHP${NC}"
        return 0
    fi

    local tmpfile
    tmpfile=$(mktemp "${TMPDIR:-/tmp}/test_proxy_regex_XXXXXX.php")
    # shellcheck disable=SC2064
    trap "rm -f '$tmpfile'" RETURN

    cat > "$tmpfile" << 'PHPEOF'
<?php
$src = file_get_contents($argv[1]);
// Extract the preg_match pattern used for image style path detection.
// Handles both single- and double-quoted pattern strings.
if (!preg_match("/preg_match\(['\"]+(#[^'\"]+#)/", $src, $pm)) {
    fwrite(STDERR, "Cannot extract image style regex from handler\n");
    exit(2);
}
$pat = $pm[1];

// Test cases: [input path, expected download path]
$cases = [
    // Styled image URL → original file path (example from the bug report)
    ['/sites/default/files/styles/medium/public/2026-02/photo.jpg',
     '/sites/default/files/2026-02/photo.jpg'],
    // Nested original path is preserved
    ['/sites/default/files/styles/thumbnail/public/subdir/image.png',
     '/sites/default/files/subdir/image.png'],
    // Non-styled path is unchanged
    ['/sites/default/files/direct/image.jpg',
     '/sites/default/files/direct/image.jpg'],
];

$fail = 0;
foreach ($cases as [$input, $expected]) {
    $download = $input;
    if (preg_match($pat, $input, $m)) {
        $download = $m[1] . '/' . $m[2];
    }
    if ($download !== $expected) {
        fwrite(STDERR, "FAIL input=$input expected=$expected got=$download\n");
        $fail = 1;
    }
}
exit($fail);
PHPEOF

    local output
    output=$(php "$tmpfile" "$HANDLER" 2>&1)
    local exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        echo -e "${GREEN}✓ Image style regex correctly maps styled paths to original file paths${NC}"
    else
        echo -e "${RED}✗ Image style regex: $output${NC}"
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
test_image_style_regex

echo -e "${GREEN}✓ PHP handler tests passed${NC}"
