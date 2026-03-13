#!/bin/bash
# Integration test for Drupal Forge deployment container
# Validates the complete flow: database import, bootstrap, file proxy

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_COMPOSE_PROJECT="test-df-deployment"
NOIMPORT_CONTAINER_NAME="${TEST_COMPOSE_PROJECT}-noimport-once"
SECURE_PRIVATE_CONTAINER_NAME="${TEST_COMPOSE_PROJECT}-secure-private-once"

# shellcheck source=lib/colors.sh
source "$SCRIPT_DIR/lib/colors.sh"

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

# shellcheck disable=SC2317  # Invoked indirectly via trap
cleanup_compose_state() {
    local remove_orphans="${1:-no}"
    local compose_down_args="-v"
    local stale_containers
    local stale_volume

    if [ "$remove_orphans" = "yes" ]; then
        compose_down_args="$compose_down_args --remove-orphans"
    fi

    # shellcheck disable=SC2086  # compose_down_args must be unquoted for word-splitting
    $DOCKER_COMPOSE -p "$TEST_COMPOSE_PROJECT" -f docker-compose.test.yml down $compose_down_args 2>/dev/null || true

    stale_containers=$(docker ps -aq --filter "label=com.docker.compose.project=${TEST_COMPOSE_PROJECT}" 2>/dev/null || true)
    if [ -n "$stale_containers" ]; then
        echo "$stale_containers" | xargs docker rm -f 2>/dev/null || true
    fi

    # Remove known named volumes explicitly in case previous interrupted runs
    # left volumes without compose metadata (which can break dependency startup).
    for stale_volume in \
        "${TEST_COMPOSE_PROJECT}_minio_data" \
        "${TEST_COMPOSE_PROJECT}_mysql_data" \
        "${TEST_COMPOSE_PROJECT}_secure_proxy_files"; do
        docker volume rm -f "$stale_volume" >/dev/null 2>&1 || true
    done
}

# shellcheck disable=SC2329  # Invoked indirectly via cleanup() from trap
cleanup_gitignored_paths() {
    local gitignore_file="$PROJECT_ROOT/.gitignore"
    local ignore_path trimmed_path

    if [ ! -f "$gitignore_file" ]; then
        return 0
    fi

    while IFS= read -r ignore_path || [ -n "$ignore_path" ]; do
        trimmed_path="${ignore_path#"${ignore_path%%[![:space:]]*}"}"
        trimmed_path="${trimmed_path%"${trimmed_path##*[![:space:]]}"}"

        if [ -z "$trimmed_path" ] || [[ "$trimmed_path" == \#* ]] || [[ "$trimmed_path" == \!* ]]; then
            continue
        fi

        if [[ "$trimmed_path" == *"*"* ]] || [[ "$trimmed_path" == *"?"* ]] || [[ "$trimmed_path" == *"["* ]]; then
            continue
        fi

        trimmed_path="${trimmed_path%/}"
        if [ -z "$trimmed_path" ] || [[ "$trimmed_path" == /* ]] || [[ "$trimmed_path" == *".."* ]]; then
            continue
        fi

        rm -rf "${PROJECT_ROOT:?}/$trimmed_path" 2>/dev/null || true
    done < "$gitignore_file"
}

# shellcheck disable=SC2329  # Invoked indirectly via trap
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
    docker rm -f "$SECURE_PRIVATE_CONTAINER_NAME" >/dev/null 2>&1 || true
    
    # Restore fixture ownership to the current (host) user before fixture cleanup
    docker run --rm \
      -v "$SCRIPT_DIR/fixtures/app:/var/www/html" \
      --user root \
      --entrypoint "" \
      test-df-deployment:8.3 \
      chown -R "$(id -u):$(id -g)" /var/www/html 2>/dev/null || true

    # Clean up test images
    echo "Removing test images..."
    $DOCKER_COMPOSE -p "$TEST_COMPOSE_PROJECT" -f docker-compose.test.yml rm -f 2>/dev/null || true
    
    # Remove dangling images created during test
    local test_images
    test_images=$(docker images -f "dangling=false" --format "{{.Repository}}:{{.Tag}}" | grep "^test-df-deployment" || true)
    if [ -n "$test_images" ]; then
        echo "$test_images" | xargs docker rmi 2>/dev/null || true
    fi

    # Remove generated paths listed in .gitignore.
    cleanup_gitignored_paths
    
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

trap cleanup EXIT

# Check dependencies
echo -e "${YELLOW}Checking dependencies...${NC}"
# Check for docker-compose (v1) or docker compose (v2)
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
    COMPOSE_UP_FLAGS=""
    echo -e "${GREEN}✓ docker-compose v1 installed${NC}"
elif docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
    COMPOSE_UP_FLAGS="--quiet-pull"
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

# Fixture initialization and ownership are handled by compose one-shot services:
# app-fixture-init and app-fixture-setup in docker-compose.test.yml.
echo -e "${YELLOW}Using compose-managed fixture initialization...${NC}"
mkdir -p "$SCRIPT_DIR/fixtures/app"
echo -e "${GREEN}✓ Fixture directory ready for compose initialization${NC}"
echo ""

# Start services
echo -e "${YELLOW}Starting test environment...${NC}"

cd "$SCRIPT_DIR"

# Ensure a clean compose state immediately before building and starting services.
cleanup_compose_state "yes"

# Build image first so we can use it to set fixture ownership
$DOCKER_COMPOSE -p "$TEST_COMPOSE_PROJECT" -f docker-compose.test.yml build

compose_up_ok=0
for start_attempt in 1 2; do
    if $DOCKER_COMPOSE -p "$TEST_COMPOSE_PROJECT" -f docker-compose.test.yml up $COMPOSE_UP_FLAGS -d; then
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
    if [ "$i" -eq 60 ]; then
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
    if [ "$i" -eq 60 ]; then
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
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T deployment sh -lc \"grep -q 'RewriteRule.*proxy-handler' /etc/apache2/sites-enabled/000-default.conf\""; then
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

# Test 9: Request a file through proxy (it should be downloaded from origin).
# Use -L so curl follows the 302 redirect that the proxy handler issues after saving the file;
# Apache then serves the file directly on the second request with correct MIME detection.
if run_test "File proxy downloads from origin" \
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T deployment curl -sL http://localhost/sites/default/files/test-file.txt | grep -q 'test file'"; then
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
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T deployment-secure curl -sL http://localhost/sites/www-data-test-files/test-file.txt | grep -q 'www-data test file'"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 14: DevPanel settings template exists in image/container
if run_test "DevPanel settings template exists in container" \
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T deployment test -f /var/www/settings.devpanel.php"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 15: Bootstrap injected DevPanel include into settings.php exactly once
if run_test "Bootstrap injected DevPanel include into settings.php once" \
    "grep -c \"settings.devpanel.php\" '$SCRIPT_DIR/fixtures/app/web/sites/default/settings.php' | grep -q '^1$'"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 16: Private file path exists and matches Apache runtime user/group
if run_test "Private file path exists and ownership matches Apache runtime user/group" \
    "$DOCKER_COMPOSE -p $TEST_COMPOSE_PROJECT -f docker-compose.test.yml exec -T deployment sh -lc 'test -d /var/www/html/private && stat -c \"%U:%G\" /var/www/html/private | grep -q \"^www:www$\"'"; then
    ((passed=passed+1))
else
    ((failed=failed+1))
fi

# Test 17: Secure-mode one-off bootstrap aligns private path ownership with default Apache user/group
echo -e "${YELLOW}Preparing secure-mode private path ownership scenario...${NC}"
docker rm -f "$SECURE_PRIVATE_CONTAINER_NAME" >/dev/null 2>&1 || true
if ! docker run -d \
    --rm \
    --name "$SECURE_PRIVATE_CONTAINER_NAME" \
    --network "${TEST_COMPOSE_PROJECT}_default" \
    -v "$SCRIPT_DIR/fixtures/app:/var/www/html" \
    -v /var/www/html/private \
    -e DB_HOST=mysql \
    -e DB_PORT=3306 \
    -e DB_USER=drupal \
    -e DB_PASSWORD=drupal_password \
    -e DB_NAME=drupaldb \
    -e DB_DRIVER=mysql \
    -e COMPOSER_INSTALL_FLAGS="--ignore-platform-req=php" \
    -e WEB_ROOT=/var/www/html/web \
    -e USE_STAGE_FILE_PROXY=no \
    test-df-deployment:8.3 >/dev/null 2>&1; then
    echo -e "${RED}✗ Failed to start secure-mode private path validation container${NC}"
    ((failed=failed+1))
else
    for i in {1..60}; do
        if docker exec "$SECURE_PRIVATE_CONTAINER_NAME" curl -s http://localhost/index.php >/dev/null 2>&1; then
            break
        fi
        if [ "$i" -eq 60 ]; then
            echo -e "${RED}✗ Timeout waiting for secure-mode private path validation container${NC}"
            docker logs --tail=100 "$SECURE_PRIVATE_CONTAINER_NAME" || true
            ((failed=failed+1))
            break
        fi
        sleep 1
    done

    if run_test "Secure-mode private path owned by default Apache user/group" \
        "docker exec $SECURE_PRIVATE_CONTAINER_NAME sh -lc 'test -d /var/www/html/private && stat -c \"%U:%G\" /var/www/html/private | grep -q \"^www-data:www-data$\"'"; then
        ((passed=passed+1))
    else
        ((failed=failed+1))
    fi

    docker rm -f "$SECURE_PRIVATE_CONTAINER_NAME" >/dev/null 2>&1 || true
fi

# Test 18: No-import installer flow skips DB setup and redirects to install start
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
