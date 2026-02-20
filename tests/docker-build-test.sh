#!/bin/bash
# Docker build tests with automatic cleanup
# Tests that Docker images build successfully for all supported PHP versions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test configuration
PHP_VERSIONS=("8.2" "8.3")
TEST_TAG_PREFIX="test-df-deployment"
BUILD_FAILED=0

echo -e "${BLUE}Testing Docker builds...${NC}"
echo ""

# Function to cleanup test images
cleanup_images() {
    echo -e "${YELLOW}Cleaning up test images...${NC}"
    for version in "${PHP_VERSIONS[@]}"; do
        local tag="${TEST_TAG_PREFIX}:${version}"
        if docker images -q "$tag" 2>/dev/null | grep -q .; then
            echo "  Removing image: $tag"
            docker rmi "$tag" 2>/dev/null || true
        fi
    done
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

# Ensure cleanup on exit
trap cleanup_images EXIT

# Test builds for each PHP version
for version in "${PHP_VERSIONS[@]}"; do
    tag="${TEST_TAG_PREFIX}:${version}"
    run_container_name="${TEST_TAG_PREFIX}-${version}"
    
    echo -e "${YELLOW}Building PHP ${version} image...${NC}"
    
    if docker build \
        --platform linux/amd64 \
        --build-arg PHP_VERSION="$version" \
        -t "$tag" \
        -f "$PROJECT_ROOT/Dockerfile" \
        "$PROJECT_ROOT" 2>&1 | grep -E "(ERROR|Successfully|DONE)" | tail -5; then
        
        echo -e "${GREEN}✓ PHP ${version} build successful${NC}"
        
        # Verify the user is set correctly
        echo -e "${YELLOW}  Verifying user configuration...${NC}"
        user_check=$(docker run --rm --entrypoint sh "$tag" -c 'whoami' 2>/dev/null)
        if [ "$user_check" == "www" ]; then
            echo -e "${GREEN}  ✓ User is 'www' (correct)${NC}"
        else
            echo -e "${RED}  ✗ User is '$user_check' (expected 'www')${NC}"
            BUILD_FAILED=1
        fi
        
        # Verify scripts are executable
        echo -e "${YELLOW}  Verifying script permissions...${NC}"
        script_check=$(docker run --rm --entrypoint sh "$tag" -c 'ls -la /usr/local/bin/deployment-entrypoint | grep "^-rwx"' 2>/dev/null)
        if [ -n "$script_check" ]; then
            echo -e "${GREEN}  ✓ Scripts have execute permissions${NC}"
        else
            echo -e "${RED}  ✗ Scripts missing execute permissions${NC}"
            BUILD_FAILED=1
        fi
        
        # Verify BASE_CMD environment variable is set
        echo -e "${YELLOW}  Verifying BASE_CMD environment...${NC}"
        base_cmd=$(docker inspect "$tag" --format='{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep "^BASE_CMD=" | cut -d= -f2-)
        if [ -n "$base_cmd" ]; then
            echo -e "${GREEN}  ✓ BASE_CMD is set: ${base_cmd}${NC}"
        else
            echo -e "${RED}  ✗ BASE_CMD environment variable not set${NC}"
            BUILD_FAILED=1
        fi
        
        # Test CMD execution: container runs with default CMD
        echo -e "${YELLOW}  Testing CMD execution...${NC}"
        docker rm -f "$run_container_name" >/dev/null 2>&1 || true
        if docker run -d --name "$run_container_name" "$tag" >/dev/null 2>&1; then
            sleep 8  # Wait for container to initialize
            
            # Check if container is still running
            if docker ps --filter "name=${run_container_name}" --format '{{.Names}}' | grep -q "$run_container_name"; then
                echo -e "${GREEN}  ✓ Container runs with default CMD${NC}"
                
                # Check if Apache is running. Allow extra startup time and match common process names.
                apache_running=0
                for _ in {1..6}; do
                    if docker exec "$run_container_name" pgrep -af "apache2|httpd" >/dev/null 2>&1; then
                        apache_running=1
                        break
                    fi
                    sleep 3
                done

                if [ "$apache_running" -eq 1 ]; then
                    echo -e "${GREEN}  ✓ Apache is running${NC}"
                else
                    logs=$(docker logs "$run_container_name" 2>&1)
                    echo -e "${RED}  ✗ Apache is not running${NC}"
                    if [ -n "$logs" ]; then
                        echo "$logs" | tail -20
                    fi
                    BUILD_FAILED=1
                fi
                
                # code-server is expected to run behind Apache in this image.
                # Keep this as a hard dependency so we don't report code-server healthy
                # while Apache detection failed.
                # Check for code-server only if enabled
                codes_enabled=$(docker exec "$run_container_name" printenv CODES_ENABLE 2>/dev/null | tr '[:upper:]' '[:lower:]')
                if [ "$codes_enabled" = "yes" ] || [ "$codes_enabled" = "true" ] || [ "$codes_enabled" = "1" ]; then
                    if [ "$apache_running" -ne 1 ]; then
                        echo -e "${RED}  ✗ code-server dependency check failed: Apache must be running when CODES_ENABLE=yes${NC}"
                        BUILD_FAILED=1
                    fi

                    code_server_running=0
                    # Retry and accept either process detection or an open HTTP listener on 8080.
                    for _ in {1..10}; do
                        if docker exec "$run_container_name" pgrep -af "code-server|coder-server|node.*code-server" >/dev/null 2>&1; then
                            code_server_running=1
                            break
                        fi

                        if docker exec "$run_container_name" sh -c '
                            if command -v curl >/dev/null 2>&1; then
                                curl -sS --max-time 2 -o /dev/null http://127.0.0.1:8080/
                            elif command -v wget >/dev/null 2>&1; then
                                wget -q -T 2 -O /dev/null http://127.0.0.1:8080/
                            else
                                exit 1
                            fi
                        ' >/dev/null 2>&1; then
                            code_server_running=1
                            break
                        fi

                        sleep 3
                    done

                    if [ "$code_server_running" -eq 1 ]; then
                        echo -e "${GREEN}  ✓ code-server started (CODES_ENABLE=yes)${NC}"
                    else
                        echo -e "${RED}  ✗ code-server not detected (CODES_ENABLE=yes)${NC}"
                        logs=$(docker logs "$run_container_name" 2>&1)
                        if [ -n "$logs" ]; then
                            echo "$logs" | tail -20
                        fi
                        BUILD_FAILED=1
                    fi
                fi
            else
                echo -e "${RED}  ✗ Container exited (should be running)${NC}"
                BUILD_FAILED=1
            fi
            
            # Cleanup container
            docker rm -f "$run_container_name" >/dev/null 2>&1
        else
            echo -e "${RED}  ✗ Failed to start container${NC}"
            BUILD_FAILED=1
        fi
        
        # Test command override
        echo -e "${YELLOW}  Testing command override...${NC}"
        override_output=$(docker run --rm "$tag" echo "Override works" 2>&1)
        if echo "$override_output" | grep -q "Override works"; then
            echo -e "${GREEN}  ✓ Command override works${NC}"
        else
            echo -e "${RED}  ✗ Command override failed${NC}"
            BUILD_FAILED=1
        fi
        
    else
        echo -e "${RED}✗ PHP ${version} build failed${NC}"
        BUILD_FAILED=1
    fi
    echo ""
done

if [ $BUILD_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All Docker builds passed${NC}"
    exit 0
else
    echo -e "${RED}✗ Some Docker builds failed${NC}"
    exit 1
fi
