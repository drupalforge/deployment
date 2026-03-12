#!/bin/bash
# Regenerates tests/markdownlint-baseline.txt from current markdownlint output.
set -e

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="${TEST_DIR%/*}"
BASELINE_FILE="$TEST_DIR/markdownlint-baseline.txt"

# shellcheck source=lib/colors.sh
source "$TEST_DIR/lib/colors.sh"

if ! command -v markdownlint >/dev/null 2>&1; then
    echo -e "${RED}✗ markdownlint not found - install markdownlint-cli: https://github.com/igorshubovych/markdownlint-cli?tab=readme-ov-file#installation${NC}"
    exit 1
fi

md_files=$(find "$SCRIPT_DIR" -type f -name "*.md" \
    ! -path "*/.git/*" \
    ! -path "*/node_modules/*" \
    ! -path "*/vendor/*" \
    ! -path "*/tests/fixtures/*")

if [ -z "$md_files" ]; then
    echo -e "${YELLOW}⊘ No Markdown files found${NC}"
    exit 0
fi

output=$(echo "$md_files" | xargs markdownlint --config "$SCRIPT_DIR/.markdownlint.json" 2>&1 || true)

{
    echo "# markdownlint baseline"
    echo "# Format: <workspace-relative-path> <rule> <count>"
    echo "# Regenerate with: bash tests/update-markdownlint-baseline.sh"
    echo ""
    echo "$output" | awk -v root="$SCRIPT_DIR/" '
        / error MD/ {
            split($0, parts, " ")
            split(parts[1], loc, ":")
            path=loc[1]
            rule=parts[3]
            sub(/\/.*/, "", rule)
            sub("^" root, "", path)
            print path, rule
        }
    ' | sort -k1,1 -k2,2 | uniq -c | awk '{print $2 " " $3 " " $1}' | sort -k1,1 -k2,2
} > "$BASELINE_FILE"

count=$(grep -vcE '^\s*(#|$)' "$BASELINE_FILE" || true)
echo -e "${GREEN}✓ markdownlint baseline updated ($count entries)${NC}"
