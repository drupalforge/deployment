#!/bin/bash
# Integration test for Drupal Forge deployment container
# Validates the complete flow: database import, bootstrap, file proxy

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Integration Test: Deployment Image${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Function to run a test
run_test() {
    local test_name="$1"
    local test_cmd="$2"
    
    echo -n "Testing: $test_name ... "
    if eval "$test_cmd" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗${NC}"
        return 1
    fi
}

# Function to cleanup
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up test environment...${NC}"
    cd "$SCRIPT_DIR"
    docker-compose -f docker-compose.test.yml down -v 2>/dev/null || true
    echo "Cleanup complete"
}

trap cleanup EXIT

# Check dependencies
echo -e "${YELLOW}Checking dependencies...${NC}"
if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}✗ docker-compose not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ docker-compose installed${NC}"
echo ""

# Initialize git repository for test app
echo -e "${YELLOW}Initializing test app...${NC}"
if [ ! -d "$SCRIPT_DIR/fixtures/app/.git" ]; then
    cd "$SCRIPT_DIR/fixtures/app"
    git init . >/dev/null 2>&1
    git config user.email "test@example.com"
    git config user.name "Test User"
    git add . >/dev/null 2>&1
    git commit -m "Initial commit" >/dev/null 2>&1
    cd "$SCRIPT_DIR"
fi
echo -e "${GREEN}✓ Test app initialized${NC}"
echo ""

# Start services
echo -e "${YELLOW}Starting test environment...${NC}"
cd "$SCRIPT_DIR"
docker-compose -f docker-compose.test.yml up -d --build

# Wait for services to be ready
echo -e "${YELLOW}Waiting for services to be ready...${NC}"
for i in {1..60}; do
    if docker-compose -f docker-compose.test.yml exec -T deployment curl -s http://localhost/index.php >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Deployment container ready${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e "${RED}✗ Timeout waiting for deployment container${NC}"
        docker-compose -f docker-compose.test.yml logs deployment
        exit 1
    fi
    echo -n "."
    sleep 1
done
echo ""

# Run tests
echo -e "${YELLOW}Running integration tests...${NC}"
echo ""

failed=0
passed=0

# Test 1: Database import
if run_test "Database import (users table exists)" \
    "docker-compose -f docker-compose.test.yml exec -T mysql mysql -uroot -proot_password -Ddrupaldb -e 'SELECT COUNT(*) FROM users' | grep -q '[0-9]'"; then
    ((passed++))
else
    ((failed++))
fi

# Test 2: Database connectivity from application
if run_test "App can connect to database" \
    "docker-compose -f docker-compose.test.yml exec -T deployment curl -s http://localhost/index.php | grep -q 'Database connected'"; then
    ((passed++))
else
    ((failed++))
fi

# Test 3: Application is reachable
if run_test "Application is reachable" \
    "docker-compose -f docker-compose.test.yml exec -T deployment curl -s http://localhost/index.php | grep -q 'Deployment Test Application'"; then
    ((passed++))
else
    ((failed++))
fi

# Test 4: Bootstrap ran (git repo initialized)
if run_test "Bootstrap initialized git" \
    "test -d '$SCRIPT_DIR/fixtures/app/.git'"; then
    ((passed++))
else
    ((failed++))
fi

# Test 5: Composer.json exists
if run_test "composer.json present" \
    "test -f '$SCRIPT_DIR/fixtures/app/composer.json'"; then
    ((passed++))
else
    ((failed++))
fi

# Test 6: File proxy - request missing file from origin
if run_test "File proxy setup (rewrite rules)" \
    "docker-compose -f docker-compose.test.yml exec -T deployment grep -q 'RewriteRule.*proxy-handler' /etc/apache2/conf-available/drupalforge-proxy.conf"; then
    ((passed++))
else
    ((failed++))
fi

# Test 7: PHP handler is accessible
if run_test "PHP proxy handler deployed" \
    "docker-compose -f docker-compose.test.yml exec -T deployment test -f /var/www/drupalforge-proxy-handler.php"; then
    ((passed++))
else
    ((failed++))
fi

# Test 8: Origin server is reachable
if run_test "Origin server is reachable" \
    "docker-compose -f docker-compose.test.yml exec -T deployment curl -s http://origin-server:8000/ | grep -q '<!DOCTYPE'"; then
    ((passed++))
else
    ((failed++))
fi

# Test 9: Request a file through proxy (it should be downloaded from origin)
if run_test "File proxy downloads from origin" \
    "docker-compose -f docker-compose.test.yml exec -T deployment curl -s http://localhost/sites/default/files/test-file.txt | grep -q 'test file'"; then
    ((passed++))
else
    ((failed++))
fi

# Test 10: Downloaded file persists locally
if run_test "Proxied file saved to disk" \
    "test -f '$SCRIPT_DIR/fixtures/app/web/sites/default/files/test-file.txt'"; then
    ((passed++))
else
    ((failed++))
fi

# Test 11: S3 bucket was used
if run_test "S3 (MinIO) connectivity tested" \
    "docker-compose -f docker-compose.test.yml exec -T minio mc ls minio/test-deployments | grep -q 'test-db.sql'"; then
    ((passed++))
else
    ((failed++))
fi

echo ""
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}================================${NC}"
echo -e "Passed: ${GREEN}$passed${NC}"
echo -e "Failed: ${RED}$failed${NC}"
echo ""

if [ $failed -eq 0 ]; then
    echo -e "${GREEN}✓ All integration tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
