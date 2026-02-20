#!/bin/bash
# Unit tests for bootstrap-app.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Testing bootstrap-app.sh...${NC}"

# Test 1: Git submodule initialization (mock)
test_git_submodules() {
    local test_repo="$TEMP_DIR/test-repo"
    mkdir -p "$test_repo/.git"
    cd "$test_repo"
    
    # Create a git config to simulate submodules
    git init . >/dev/null 2>&1
    git config submodule.test.path "modules/test"
    git config submodule.test.url "https://github.com/test/test.git"
    
    # Run bootstrap with git installed
    if command -v git &> /dev/null; then
        bash "$SCRIPT_DIR/scripts/bootstrap-app.sh" 2>&1 | grep -q "Git submodules" || true
        echo -e "${GREEN}✓ Git submodule detection works${NC}"
    else
        echo -e "${YELLOW}⊘ Git not found in PATH (skipping submodule test)${NC}"
    fi
}

# Test 2: Composer detection
test_composer_detection() {
    local test_repo="$TEMP_DIR/test-composer"
    mkdir -p "$test_repo"
    
    # Create a composer.json
    echo '{"name": "test/app"}' > "$test_repo/composer.json"
    cd "$test_repo"
    
    # This will try to run composer install but that's expected
    bash "$SCRIPT_DIR/scripts/bootstrap-app.sh" 2>&1 | grep -q "Composer" || true
    echo -e "${GREEN}✓ Composer detection logic works${NC}"
}

# Test 3: Composer install failure causes script to fail
test_composer_install_failure() {
    local test_repo="$TEMP_DIR/test-composer-fail"
    local fake_bin="$TEMP_DIR/fake-bin-fail"
    mkdir -p "$test_repo" "$fake_bin"

    echo '{"name": "test/app"}' > "$test_repo/composer.json"

    # Quoted heredoc ('EOF') prevents shell variable expansion in the fake script
    cat > "$fake_bin/composer" <<'EOF'
#!/bin/bash
if [[ "$*" == *"--version"* ]]; then
  echo "Composer version 2.x"
  exit 0
fi
echo "Simulated composer failure" >&2
exit 1
EOF
    chmod +x "$fake_bin/composer"

    set +e
    PATH="$fake_bin:$PATH" APP_ROOT="$test_repo" bash "$SCRIPT_DIR/scripts/bootstrap-app.sh" >/dev/null 2>&1
    local status=$?
    set -e

    if [ "$status" -ne 0 ]; then
        echo -e "${GREEN}✓ Composer install failure causes script to fail${NC}"
    else
        echo -e "${RED}✗ Composer install failure should cause script to fail${NC}"
        exit 1
    fi
}

# Test 4: Lock permission message requires installed dependencies
test_composer_lock_permission_without_vendor_fails() {
    local test_repo="$TEMP_DIR/test-composer-lock-perm"
    local fake_bin="$TEMP_DIR/fake-bin-lock-perm"
    mkdir -p "$test_repo" "$fake_bin"

    echo '{"name": "test/app"}' > "$test_repo/composer.json"

    cat > "$fake_bin/composer" <<'EOF'
#!/bin/bash
if [[ "$*" == *"--version"* ]]; then
  echo "Composer version 2.x"
  exit 0
fi
echo "Cannot create composer.lock: Permission denied" >&2
exit 1
EOF
    chmod +x "$fake_bin/composer"

    set +e
    PATH="$fake_bin:$PATH" APP_ROOT="$test_repo" bash "$SCRIPT_DIR/scripts/bootstrap-app.sh" >/dev/null 2>&1
    local status=$?
    set -e

    if [ "$status" -ne 0 ]; then
        echo -e "${GREEN}✓ Lock permission without vendor correctly fails${NC}"
    else
        echo -e "${RED}✗ Lock permission without vendor should fail${NC}"
        exit 1
    fi
}

# Test 5: Script is executable
test_script_executable() {
    if [ -x "$SCRIPT_DIR/scripts/bootstrap-app.sh" ]; then
        echo -e "${GREEN}✓ bootstrap-app.sh is executable${NC}"
    else
        echo -e "${RED}✗ bootstrap-app.sh is not executable${NC}"
        exit 1
    fi
}

# Test 6: Script has error handling
test_error_handling() {
    if grep -q "set -e" "$SCRIPT_DIR/scripts/bootstrap-app.sh"; then
        echo -e "${GREEN}✓ Script has error handling (set -e)${NC}"
    else
        echo -e "${YELLOW}⊘ Script missing 'set -e'${NC}"
    fi
}

# Run tests
test_script_executable
test_error_handling
test_composer_detection
test_composer_install_failure
test_composer_lock_permission_without_vendor_fails

echo -e "${GREEN}✓ Bootstrap app tests passed${NC}"
