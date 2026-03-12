#!/bin/bash
# Tests for Markdown file linting
#
# This test validates Markdown formatting and style consistency.
set -e

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${TEST_DIR%/*}"

# shellcheck source=lib/colors.sh
source "$TEST_DIR/lib/colors.sh"

echo -e "${BLUE}Testing Markdown files...${NC}"

# Test 1: markdownlint is available
test_markdownlint_available() {
    if command -v markdownlint >/dev/null 2>&1; then
        local version
        version=$(markdownlint --version 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓ markdownlint is available (version $version)${NC}"
    else
        echo -e "${RED}✗ markdownlint not found - install markdownlint-cli: https://github.com/igorshubovych/markdownlint-cli?tab=readme-ov-file#installation${NC}"
        exit 1
    fi
}

# Test 2: markdownlint config exists
test_markdownlint_config_exists() {
    if [ -f "$SCRIPT_DIR/.markdownlint.json" ]; then
        echo -e "${GREEN}✓ .markdownlint.json config exists${NC}"
    else
        echo -e "${RED}✗ .markdownlint.json config not found${NC}"
        exit 1
    fi
}

# Test 3: Lint all Markdown files
test_markdown_files() {
    local baseline_file="$TEST_DIR/markdownlint-baseline.txt"
    local md_files
    md_files=$(find "$SCRIPT_DIR" -type f -name "*.md" \
        ! -path "*/.git/*" \
        ! -path "*/node_modules/*" \
        ! -path "*/vendor/*" \
        ! -path "*/tests/fixtures/*")

    if [ -z "$md_files" ]; then
        echo -e "${YELLOW}⊘ No Markdown files found${NC}"
        return 0
    fi

    local file_count
    file_count=$(echo "$md_files" | wc -l | xargs)
    echo -e "${BLUE}  Linting $file_count Markdown file(s)...${NC}"

    if [ ! -f "$baseline_file" ]; then
        echo -e "${RED}✗ markdownlint baseline not found: tests/markdownlint-baseline.txt${NC}"
        exit 1
    fi

    local output
    local current_keys
    local baseline_keys
    local unexpected_keys
    local resolved_keys
    local tmp_current
    local tmp_baseline
    local tmp_unexpected

    tmp_current=$(mktemp)
    tmp_baseline=$(mktemp)
    tmp_unexpected=$(mktemp)

    if output=$(echo "$md_files" | xargs markdownlint --config "$SCRIPT_DIR/.markdownlint.json" 2>&1); then
        current_keys=""
    else
        current_keys=$(echo "$output" | awk -v root="$SCRIPT_DIR/" '
            / error MD/ {
                split($0, parts, " ")
                split(parts[1], loc, ":")
                path=loc[1]
                rule=parts[3]
                sub(/\/.*/, "", rule)
                sub("^" root, "", path)
                print path, rule
            }
        ' | sort -k1,1 -k2,2 | uniq -c | awk '{print $2 " " $3 " " $1}' | sort -k1,1 -k2,2)
    fi

    baseline_keys=$(grep -vE '^\s*(#|$)' "$baseline_file" | sort -k1,1 -k2,2)

    printf "%s\n" "$current_keys" | sed '/^$/d' > "$tmp_current"
    printf "%s\n" "$baseline_keys" | sed '/^$/d' > "$tmp_baseline"

    unexpected_keys=$(comm -23 "$tmp_current" "$tmp_baseline")
    resolved_keys=$(comm -13 "$tmp_current" "$tmp_baseline")

    if [ -n "$resolved_keys" ]; then
        local resolved_count
        resolved_count=$(echo "$resolved_keys" | wc -l | xargs)
        echo -e "${YELLOW}⊘ Baseline entries resolved: $resolved_count (run tests/update-markdownlint-baseline.sh)${NC}"
    fi

    if echo "$unexpected_keys" | grep -q '[^[:space:]]'; then
        echo "$unexpected_keys" > "$tmp_unexpected"
        echo -e "${RED}✗ Markdown linting found new file/rule counts not in baseline${NC}"
        echo ""
        cat "$tmp_unexpected"
        echo ""
        echo "To update baseline after intentional fixes:"
        echo "  bash tests/update-markdownlint-baseline.sh"
        rm -f "$tmp_current" "$tmp_baseline" "$tmp_unexpected"
        exit 1
    fi

    rm -f "$tmp_current" "$tmp_baseline" "$tmp_unexpected"
    echo -e "${GREEN}✓ Markdown files match baseline (no new lint violations)${NC}"
}

test_markdownlint_available
test_markdownlint_config_exists
test_markdown_files
echo -e "${GREEN}✓ Markdown lint tests passed${NC}"
