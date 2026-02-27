#!/bin/bash
# Integration test for Drupal Forge deployment container
# Validates the complete flow: database import, bootstrap, file proxy

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_COMPOSE_PROJECT="test-df-deployment"
NOIMPORT_CONTAINER_NAME="${TEST_COMPOSE_PROJECT}-noimport-once"

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

cleanup_compose_state() {
    local remove_orphans="${1:-no}"
    local compose_down_args="-v"
    local stale_containers

    if [ "$remove_orphans" = "yes" ]; then
        compose_down_args="$compose_down_args --remove-orphans"
    fi

    $DOCKER_COMPOSE -p "$TEST_COMPOSE_PROJECT" -f docker-compose.test.yml down $compose_down_args 2>/dev/null || true

    stale_containers=$(docker ps -aq --filter "label=com.docker.compose.project=${TEST_COMPOSE_PROJECT}" 2>/dev/null || true)
    if [ -n "$stale_containers" ]; then
        echo "$stale_containers" | xargs docker rm -f 2>/dev/null || true
    fi
}

# Function to cleanup
cleanup() {
    if [ "${KEEP_TEST_ENV:-no}" = "yes" ]; then
        echo ""
        echo -e "${YELLOW}KEEP_TEST_ENV=yes set; skipping cleanup for debugging${NC}"
        return
    fi

    echo ""
    echo -e "${YELLOW}Cleaning up test environment...${NC}"
    cd "$SCRIPT_DIR"
    
    # Stop and remove compose resources for this test project.
    cleanup_compose_state "no"

    # Best-effort cleanup for one-off no-import validation container.
    docker rm -f "$NOIMPORT_CONTAINER_NAME" >/dev/null 2>&1 || true
    
    # Restore fixture ownership to the current (host) user before fixture cleanup
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
        echo "$test_images" | xargs docker rmi 2>/dev/null || true
    fi

    # Remove integration fixture app directory.
    rm -rf "$SCRIPT_DIR/fixtures/app" 2>/dev/null || true
    
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

# Best-effort stale cleanup before building/running to avoid memory pressure
# from interrupted prior runs.
echo -e "${YELLOW}Cleaning stale integration resources...${NC}"
cleanup_compose_state "yes"
echo -e "${GREEN}✓ Stale resources cleaned${NC}"
echo ""

# Check Docker memory allocation (integration stack is memory-intensive on macOS Docker Desktop).
docker_mem_bytes=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
if [[ "$docker_mem_bytes" =~ ^[0-9]+$ ]] && [ "$docker_mem_bytes" -gt 0 ]; then
    docker_mem_mb=$((docker_mem_bytes / 1024 / 1024))
    if [ "$docker_mem_mb" -lt 3072 ]; then
        echo -e "${BLUE}  Docker memory is ${docker_mem_mb} MiB; integration is more reliable with >= 3072 MiB${NC}"
    fi
fi

# Initialize test app from Drupal 11 recommended-project
echo -e "${YELLOW}Initializing test app...${NC}"
if [ ! -f "$SCRIPT_DIR/fixtures/app/composer.json" ]; then
    # Clean up any partial/failed installation
    rm -rf "$SCRIPT_DIR/fixtures/app"
    mkdir -p "$SCRIPT_DIR/fixtures/app"
    cd "$SCRIPT_DIR/fixtures/app"
    
    # Clone Drupal 11 recommended-project (shallow clone for speed)
    git clone --branch 11.x --single-branch --depth 1 \
        https://github.com/drupal/recommended-project.git . >/dev/null 2>&1
    
    # Install dependencies including Drush and Stage File Proxy
    composer require drush/drush drupal/stage_file_proxy \
        --no-interaction >/dev/null 2>&1

    cd "$SCRIPT_DIR"
fi

# Ensure fixture has settings.php (existing fixture checkouts skip the block above).
# Bootstrap intentionally does not auto-create settings.php when default.settings.php
# existed before bootstrap started, so integration fixtures must provide it.
if [ ! -f "$SCRIPT_DIR/fixtures/app/web/sites/default/settings.php" ] && [ -f "$SCRIPT_DIR/fixtures/app/web/sites/default/default.settings.php" ]; then
    cp "$SCRIPT_DIR/fixtures/app/web/sites/default/default.settings.php" "$SCRIPT_DIR/fixtures/app/web/sites/default/settings.php"
fi

# Ensure the default files directory exists and is writable after fresh fixture
# recreation. On macOS bind mounts, UID/GID mapping can make container writes
# fail unless explicit write permissions are set on the host path.
mkdir -p "$SCRIPT_DIR/fixtures/app/web/sites/default/files"
chmod -R a+rwX "$SCRIPT_DIR/fixtures/app/web/sites/default/files" 2>/dev/null || true
echo -e "${GREEN}✓ Test app initialized${NC}"
echo ""

# Start services
echo -e "${YELLOW}Starting test environment...${NC}"

cd "$SCRIPT_DIR"

# Ensure a clean compose state immediately before building and starting services.
cleanup_compose_state "yes"

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
    chown -R www:www /var/www/html 2>/dev/null || true
echo -e "${GREEN}✓ Fixture ownership set for container user${NC}"

compose_up_ok=0
for start_attempt in 1 2; do
    if $DOCKER_COMPOSE -p "$TEST_COMPOSE_PROJECT" -f docker-compose.test.yml up -d; then
        compose_up_ok=1
        break
    fi

    echo -e "${BLUE}  Compose startup attempt ${start_attempt} failed; capturing mysql logs${NC}"
    $DOCKER_COMPOSE -p "$TEST_COMPOSE_PROJECT" -f docker-compose.test.yml ps || true
    $DOCKER_COMPOSE -p "$TEST_COMPOSE_PROJECT" -f docker-compose.test.yml logs mysql --tail=200 || true

    if [ "$start_attempt" -lt 2 ]; then
        echo -e "${BLUE}  Retrying startup with clean services/volumes${NC}"
        cleanup_compose_state "yes"
    fi
done

if [ "$compose_up_ok" -ne 1 ]; then
    echo -e "${RED}✗ Failed to start integration environment after retries${NC}"
    exit 1
fi

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

# Test 2: Installer endpoint is reachable and reports a valid Drupal install state
# Depending on fixture DB snapshot, Drupal may report either installer flow or already-installed state.
if run_test "Drupal install state endpoint reachable" \
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T deployment sh -lc 'curl -sL http://localhost/core/install.php | grep -Eqi \"(already installed|choose language|set up database)\"'"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 3: Drupal entrypoint responds
if run_test "Drupal index endpoint reachable" \
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T deployment sh -lc 'curl -sL http://localhost/index.php | grep -qi \"Drupal\"'"; then
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
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T deployment sh -lc \"grep -q 'RewriteRule.*proxy-handler' /etc/apache2/conf-available/drupalforge-proxy.conf || grep -q 'RewriteRule.*proxy-handler' /var/www/html/web/.htaccess\""; then
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
    "grep -c \"/usr/local/share/drupalforge/settings.devpanel.php\" '$SCRIPT_DIR/fixtures/app/web/sites/default/settings.php' | grep -q '^1$'"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 16: No-import installer flow skips DB setup and redirects to install start
echo -e "${YELLOW}Preparing no-import installer flow scenario...${NC}"
if ! $DOCKER_COMPOSE -p "$TEST_COMPOSE_PROJECT" -f docker-compose.test.yml exec -T mysql \
    mysql -uroot -proot_password -e "DROP DATABASE IF EXISTS drupaldb_noimport; CREATE DATABASE drupaldb_noimport; GRANT ALL PRIVILEGES ON drupaldb_noimport.* TO 'drupal'@'%'; FLUSH PRIVILEGES;" >/dev/null 2>&1; then
    echo -e "${RED}✗ Failed to prepare empty installer test database${NC}"
    ((failed=failed+1))
else
    docker rm -f "$NOIMPORT_CONTAINER_NAME" >/dev/null 2>&1 || true
    # Use a one-off container from the same built image rather than mutating
    # the primary deployment service state. This keeps proxy/import assertions
    # deterministic and isolates no-import installer validation.
    if ! docker run -d \
        --platform linux/amd64 \
        --name "$NOIMPORT_CONTAINER_NAME" \
        --network "${TEST_COMPOSE_PROJECT}_default" \
        -v "$SCRIPT_DIR/fixtures/app:/var/www/html" \
        -e APACHE_RUN_USER=www \
        -e APACHE_RUN_GROUP=www \
        -e DB_HOST=mysql \
        -e DB_PORT=3306 \
        -e DB_USER=drupal \
        -e DB_PASSWORD=drupal_password \
        -e DB_NAME=drupaldb_noimport \
        -e DB_DRIVER=mysql \
        -e COMPOSER_INSTALL_FLAGS="--ignore-platform-req=php" \
        -e WEB_ROOT=/var/www/html/web \
        -e USE_STAGE_FILE_PROXY=no \
        test-df-deployment:8.3 >/dev/null 2>&1; then
        echo -e "${RED}✗ Failed to start no-import validation container${NC}"
        ((failed=failed+1))
    else
        for i in {1..60}; do
            if docker exec "$NOIMPORT_CONTAINER_NAME" curl -s http://localhost/index.php >/dev/null 2>&1; then
                break
            fi
            if [ "$i" -eq 60 ]; then
                echo -e "${RED}✗ Timeout waiting for no-import validation container${NC}"
                docker logs --tail=100 "$NOIMPORT_CONTAINER_NAME" || true
                ((failed=failed+1))
                break
            fi
            sleep 1
        done

        if run_test "No-import installer flow skips database setup" \
            "docker exec $NOIMPORT_CONTAINER_NAME sh -lc 'location=\"\$(curl -sI \"http://localhost/core/install.php?rewrite=ok&langcode=en&profile=minimal\" | tr -d \"\\r\" | awk -F\": \" '\''tolower(\$1)==\"location\" {print \$2; exit}'\'')\" && echo \"\$location\" | grep -q \"op=start\"'"; then
            ((passed=passed+1))
        else
            ((failed=failed+1))
        fi

        docker rm -f "$NOIMPORT_CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
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
