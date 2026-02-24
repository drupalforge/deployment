#!/bin/bash
# Integration test for Drupal Forge deployment container
# Validates the complete flow: database import, bootstrap, file proxy

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_COMPOSE_PROJECT="test-df-deployment"
FIXTURES_PATH="tests/fixtures/app"
FIXTURE_GITIGNORE="$SCRIPT_DIR/fixtures/app/.gitignore"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE}Integration Test: Deployment Image${NC}"
echo -e "${BLUE}==================================${NC}"
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
    
    # Stop and remove containers, networks, volumes
    $DOCKER_COMPOSE -p "$TEST_COMPOSE_PROJECT" -f docker-compose.test.yml down -v 2>/dev/null || true
    
    # Restore fixture ownership to the current (host) user so git clean can remove generated files
    docker run --rm \
      --platform linux/amd64 \
      -v "$SCRIPT_DIR/fixtures/app:/var/www/html" \
      --user root \
      --entrypoint "" \
      test-df-deployment:8.3 \
      chown -R "$(id -u):$(id -g)" /var/www/html 2>/dev/null || true

    # Clean up test images
    echo "Removing test images..."
    $DOCKER_COMPOSE -p "$TEST_COMPOSE_PROJECT" -f docker-compose.test.yml rm -f 2>/dev/null || true
    
    # Remove dangling images created during test
    local test_images=$(docker images -f "dangling=false" --format "{{.Repository}}:{{.Tag}}" | grep "^test-df-deployment" || true)
    if [ -n "$test_images" ]; then
        echo "$test_images" | xargs -r docker rmi 2>/dev/null || true
    fi

    # Remove temporary fixture .gitignore so git can restore tracked files
    rm -f "$FIXTURE_GITIGNORE"

    # Remove generated files written through bind-mounted fixtures/app volume
    # Restore tracked fixture files and remove untracked files.
    if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$PROJECT_ROOT" checkout -- "$FIXTURES_PATH" >/dev/null 2>&1 || true
        git -C "$PROJECT_ROOT" clean -df -- "$FIXTURES_PATH" >/dev/null 2>&1 || true
    else
        rm -rf "$SCRIPT_DIR/fixtures/app/web/sites" 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

trap cleanup EXIT

# Check dependencies
echo -e "${YELLOW}Checking dependencies...${NC}"
# Check for docker-compose (v1) or docker compose (v2)
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
    echo -e "${GREEN}✓ docker-compose v1 installed${NC}"
elif docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
    echo -e "${GREEN}✓ docker compose v2 installed${NC}"
else
    echo -e "${RED}✗ docker-compose or docker compose not found${NC}"
    exit 1
fi
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

# Remove temporary fixture .gitignore from any previous failed run
rm -f "$FIXTURE_GITIGNORE"

# Restore fixture baseline from Git
if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$PROJECT_ROOT" checkout -- "$FIXTURES_PATH" >/dev/null 2>&1 || true
    git -C "$PROJECT_ROOT" clean -df -- "$FIXTURES_PATH" >/dev/null 2>&1 || true
fi

# Create temporary .gitignore to isolate fixture mutations from host git status
echo '*' > "$FIXTURE_GITIGNORE"

cd "$SCRIPT_DIR"
$DOCKER_COMPOSE -p "$TEST_COMPOSE_PROJECT" -f docker-compose.test.yml down -v --remove-orphans 2>/dev/null || true

# Build image first so we can use it to set fixture ownership
$DOCKER_COMPOSE -p "$TEST_COMPOSE_PROJECT" -f docker-compose.test.yml build

# Ensure fixture app directory is owned by the container user (www=uid 1000)
# so that Composer can create the vendor/ directory during bootstrap
docker run --rm \
  --platform linux/amd64 \
  -v "$SCRIPT_DIR/fixtures/app:/var/www/html" \
  --user root \
  --entrypoint "" \
  test-df-deployment:8.3 \
  chown -R www:www /var/www/html
echo -e "${GREEN}✓ Fixture ownership set for container user${NC}"

$DOCKER_COMPOSE -p "$TEST_COMPOSE_PROJECT" -f docker-compose.test.yml up -d

# Wait for regular deployment container to be ready
echo -e "${YELLOW}Waiting for services to be ready...${NC}"
for i in {1..60}; do
    if $DOCKER_COMPOSE -p "$TEST_COMPOSE_PROJECT" -f docker-compose.test.yml exec -T deployment curl -s http://localhost/index.php >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Deployment container ready${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e "${RED}✗ Timeout waiting for deployment container${NC}"
        $DOCKER_COMPOSE -p "$TEST_COMPOSE_PROJECT" -f docker-compose.test.yml logs deployment
        exit 1
    fi
    echo -n "."
    sleep 1
done
echo ""

# Wait for secure deployment container to be ready
for i in {1..60}; do
    if $DOCKER_COMPOSE -p "$TEST_COMPOSE_PROJECT" -f docker-compose.test.yml exec -T deployment-secure curl -s http://localhost/index.php >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Secure deployment container ready${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e "${RED}✗ Timeout waiting for secure deployment container${NC}"
        $DOCKER_COMPOSE -p "$TEST_COMPOSE_PROJECT" -f docker-compose.test.yml logs deployment-secure
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
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T mysql mysql -uroot -proot_password -Ddrupaldb -e 'SELECT COUNT(*) FROM users' | grep -q '[0-9]'"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 2: Database connectivity from application
if run_test "App can connect to database" \
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T deployment curl -s http://localhost/index.php | grep -q 'Database connected'"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 3: Application is reachable
if run_test "Application is reachable" \
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T deployment curl -s http://localhost/index.php | grep -q 'Deployment Test Application'"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 4: Bootstrap ran (git repo initialized)
if run_test "Bootstrap initialized git" \
    "test -d '$SCRIPT_DIR/fixtures/app/.git'"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 5: Composer.json exists
if run_test "composer.json present" \
    "test -f '$SCRIPT_DIR/fixtures/app/composer.json'"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 6: File proxy - request missing file from origin
if run_test "File proxy setup (rewrite rules)" \
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T deployment grep -q 'RewriteRule.*proxy-handler' /etc/apache2/conf-available/drupalforge-proxy.conf"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 7: PHP handler is accessible
if run_test "PHP proxy handler deployed" \
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T deployment test -f /var/www/drupalforge-proxy-handler.php"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 8: Origin server is reachable
if run_test "Origin server is reachable" \
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T deployment curl -s http://origin-server:8000/ | grep -q '<!DOCTYPE'"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 9: Request a file through proxy (it should be downloaded from origin)
if run_test "File proxy downloads from origin" \
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T deployment curl -s http://localhost/sites/default/files/test-file.txt | grep -q 'test file'"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 10: Downloaded file persists locally
if run_test "Proxied file saved to disk" \
    "test -f '$SCRIPT_DIR/fixtures/app/web/sites/default/files/test-file.txt'"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 11: S3 bucket was used
if run_test "S3 (MinIO) connectivity tested" \
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T deployment sh -lc 'aws s3 ls --endpoint-url=\"\$AWS_S3_ENDPOINT\" s3://\$S3_BUCKET/' | grep -q 'test-db.sql'"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 12: Secure (www-data default) - proxy path directory is owned by www-data
if run_test "Secure (Apache www-data default): proxy path owned by www-data" \
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T deployment-secure stat -c '%U' /var/www/html/web/sites/www-data-test-files | grep -q 'www-data'"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 13: Secure (www-data default) - Apache can write proxy-downloaded files as www-data
if run_test "Secure (Apache www-data default): file proxy downloads from origin" \
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T deployment-secure curl -s http://localhost/sites/www-data-test-files/test-file.txt | grep -q 'www-data test file'"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 14: DevPanel settings template exists in image/container
if run_test "DevPanel settings template exists in container" \
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T deployment test -f /usr/local/share/drupalforge/settings.devpanel.php"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 15: Bootstrap injected DevPanel include into settings.php exactly once
if run_test "Bootstrap injected DevPanel include into settings.php once" \
    "grep -c \"getenv('DP_APP_ID')\" '$SCRIPT_DIR/fixtures/app/web/sites/default/settings.php' | grep -q '^1$'"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

echo ""
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}================================${NC}"
if [ $passed -eq 0 ]; then
    echo "Passed: $passed"
else
    echo -e "Passed: ${GREEN}$passed${NC}"
fi

if [ $failed -eq 0 ]; then
    echo "Failed: $failed"
else
    echo -e "Failed: ${RED}$failed${NC}"
fi
echo ""

if [ $failed -eq 0 ]; then
    echo -e "${GREEN}✓ All integration tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
