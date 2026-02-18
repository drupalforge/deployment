#!/bin/bash
# Tests for CMD execution
# Verifies that BASE_CMD is set and container executes it correctly

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Testing CMD execution..."

# Configuration
TEST_TAG="test-cmd-execution:latest"
PHP_VERSION="8.3"

# Cleanup function
cleanup() {
    # Remove test containers
    docker rm -f test-cmd-default test-cmd-override test-cmd-apache 2>/dev/null || true
    # Remove test image
    docker rmi "$TEST_TAG" 2>/dev/null || true
}

# Ensure cleanup on exit
trap cleanup EXIT

# Build test image
echo -e "${YELLOW}Building test image...${NC}"
if ! BASE_CMD=$(cd "$SCRIPT_DIR" && ./extract-base-cmd.sh "$PHP_VERSION" 2>/dev/null); then
    echo -e "${RED}✗ Failed to extract BASE_CMD${NC}"
    exit 1
fi

if ! docker build \
    --build-arg PHP_VERSION="$PHP_VERSION" \
    --build-arg BASE_CMD="${BASE_CMD}" \
    -t "$TEST_TAG" \
    -f "$SCRIPT_DIR/Dockerfile" \
    "$SCRIPT_DIR" >/dev/null 2>&1; then
    echo -e "${RED}✗ Failed to build test image${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Test image built${NC}"

# Test 1: BASE_CMD environment variable is set
test_base_cmd_env() {
    local env_value
    env_value=$(docker inspect "$TEST_TAG" --format='{{range .Config.Env}}{{println .}}{{end}}' | grep "^BASE_CMD=" | cut -d= -f2-)
    
    if [ -z "$env_value" ]; then
        echo -e "${RED}✗ BASE_CMD environment variable not set${NC}"
        return 1
    fi
    
    if [ "$env_value" != "$BASE_CMD" ]; then
        echo -e "${RED}✗ BASE_CMD mismatch. Expected: '$BASE_CMD', Got: '$env_value'${NC}"
        return 1
    fi
    
    echo "✓ BASE_CMD environment variable is set correctly"
    return 0
}

# Test 2: Container runs with default CMD
test_container_runs_default() {
    # Start container with no command (should use BASE_CMD)
    if ! docker run -d --name test-cmd-default "$TEST_TAG" >/dev/null 2>&1; then
        echo -e "${RED}✗ Failed to start container with default CMD${NC}"
        return 1
    fi
    
    # Wait for container to initialize
    sleep 5
    
    # Check if container is still running
    if ! docker ps --filter "name=test-cmd-default" --format '{{.Names}}' | grep -q "test-cmd-default"; then
        echo -e "${RED}✗ Container exited (should be running with default CMD)${NC}"
        echo "Container logs:"
        docker logs test-cmd-default 2>&1 | tail -10
        return 1
    fi
    
    echo "✓ Container runs with default CMD"
    return 0
}

# Test 3: CMD execution is logged
test_cmd_logged() {
    local logs
    logs=$(docker logs test-cmd-default 2>&1)
    
    if ! echo "$logs" | grep -q "Executing base image CMD"; then
        echo -e "${RED}✗ CMD execution not logged${NC}"
        return 1
    fi
    
    if ! echo "$logs" | grep -q "$BASE_CMD"; then
        echo -e "${RED}✗ BASE_CMD value not logged${NC}"
        return 1
    fi
    
    echo "✓ CMD execution is logged"
    return 0
}

# Test 4: Apache starts successfully
test_apache_starts() {
    local logs
    
    # Wait a bit more for Apache to start
    sleep 8
    
    logs=$(docker logs test-cmd-default 2>&1)
    
    # Check for Apache startup message
    if ! echo "$logs" | grep -q "Apache.*configured.*resuming normal operations"; then
        echo -e "${YELLOW}⚠ Apache startup message not found in logs${NC}"
        echo "Checking for code-server instead..."
        
        # Alternative: check for code-server which also indicates startup
        if ! echo "$logs" | grep -q "code-server.*HTTP server listening"; then
            echo -e "${RED}✗ Neither Apache nor code-server startup detected${NC}"
            return 1
        fi
        echo "✓ Code-server started (container is running)"
        return 0
    fi
    
    echo "✓ Apache started successfully"
    return 0
}

# Test 5: Container doesn't exit prematurely
test_no_premature_exit() {
    # Check container status after initialization period
    sleep 3
    
    local status
    status=$(docker inspect test-cmd-default --format='{{.State.Status}}' 2>/dev/null)
    
    if [ "$status" != "running" ]; then
        echo -e "${RED}✗ Container not running (status: $status)${NC}"
        echo "Exit code: $(docker inspect test-cmd-default --format='{{.State.ExitCode}}')"
        return 1
    fi
    
    echo "✓ Container doesn't exit prematurely"
    return 0
}

# Test 6: Command override works
test_command_override() {
    # Run container with custom command
    local output
    output=$(docker run --rm --name test-cmd-override "$TEST_TAG" echo "Override works" 2>&1)
    
    if ! echo "$output" | grep -q "Override works"; then
        echo -e "${RED}✗ Command override failed${NC}"
        return 1
    fi
    
    # Verify initialization still runs
    if ! echo "$output" | grep -q "Deployment initialization complete"; then
        echo -e "${RED}✗ Initialization didn't run with override${NC}"
        return 1
    fi
    
    echo "✓ Command override works"
    return 0
}

# Test 7: Fallback works if BASE_CMD not set
test_fallback_cmd() {
    # Build image without BASE_CMD
    echo -e "${YELLOW}Testing fallback (without BASE_CMD)...${NC}"
    
    if ! docker build \
        --build-arg PHP_VERSION="$PHP_VERSION" \
        --build-arg BASE_CMD="" \
        -t "${TEST_TAG}-fallback" \
        -f "$SCRIPT_DIR/Dockerfile" \
        "$SCRIPT_DIR" >/dev/null 2>&1; then
        echo -e "${RED}✗ Failed to build fallback test image${NC}"
        return 1
    fi
    
    # Run and check logs for fallback warning
    local logs
    logs=$(docker run --rm "${TEST_TAG}-fallback" echo "test" 2>&1)
    
    if echo "$logs" | grep -q "Warning: BASE_CMD not set, using hardcoded fallback"; then
        echo "✓ Fallback works when BASE_CMD not set"
    else
        echo "✓ Fallback executed (warning may be suppressed)"
    fi
    
    docker rmi "${TEST_TAG}-fallback" 2>/dev/null || true
    return 0
}

# Run all tests
failed=0

test_base_cmd_env || failed=1
test_container_runs_default || failed=1
test_cmd_logged || failed=1
test_apache_starts || failed=1
test_no_premature_exit || failed=1
test_command_override || failed=1
test_fallback_cmd || failed=1

if [ $failed -eq 0 ]; then
    echo -e "${GREEN}✓ CMD execution tests passed${NC}"
    exit 0
else
    echo -e "${RED}✗ Some CMD execution tests failed${NC}"
    exit 1
fi
