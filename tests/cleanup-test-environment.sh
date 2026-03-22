#!/bin/bash
# Shared cleanup for integration and manual compose test environments.
#
# Modes:
#   --mode stale : pre-run cleanup (aggressive compose/container/volume cleanup)
#   --mode full  : post-run cleanup (stale cleanup + fixture/image cleanup)
#   --mode docker-build : cleanup docker-build-test containers/images

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/colors.sh
source "$SCRIPT_DIR/lib/colors.sh"

MODE="full"
PROJECT_NAME="$(basename "$SCRIPT_DIR")"
COMPOSE_FILE="docker-compose.test.yml"
TAG_PREFIX="test-df-deployment"
PHP_VERSIONS="8.2 8.3"

usage() {
    echo "Usage: $0 [--mode stale|full|docker-build] [--project NAME] [--compose-file FILE] [--tag-prefix PREFIX] [--php-versions \"8.2 8.3\"]"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --mode)
            MODE="${2:-}"
            shift 2
            ;;
        --project)
            PROJECT_NAME="${2:-}"
            shift 2
            ;;
        --compose-file)
            COMPOSE_FILE="${2:-}"
            shift 2
            ;;
        --tag-prefix)
            TAG_PREFIX="${2:-}"
            shift 2
            ;;
        --php-versions)
            PHP_VERSIONS="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}[ERROR] Unknown argument: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

if [ "$MODE" != "stale" ] && [ "$MODE" != "full" ] && [ "$MODE" != "docker-build" ]; then
    echo -e "${RED}[ERROR] --mode must be 'stale', 'full', or 'docker-build'${NC}"
    exit 1
fi

if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE=(docker-compose)
elif docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE=(docker compose)
else
    echo -e "${RED}[ERROR] docker-compose or docker compose not found${NC}"
    exit 1
fi

if [[ "$COMPOSE_FILE" = /* ]]; then
    COMPOSE_FILE_PATH="$COMPOSE_FILE"
else
    COMPOSE_FILE_PATH="$SCRIPT_DIR/$COMPOSE_FILE"
fi

cleanup_compose_state() {
    local remove_orphans="$1"
    local stale_containers
    local stale_volume
    local down_args=(-p "$PROJECT_NAME" -f "$COMPOSE_FILE_PATH" down -v)

    if [ "$remove_orphans" = "yes" ]; then
        down_args+=(--remove-orphans)
    fi

    "${DOCKER_COMPOSE[@]}" "${down_args[@]}" >/dev/null 2>&1 || true

    stale_containers=$(docker ps -aq --filter "label=com.docker.compose.project=${PROJECT_NAME}" 2>/dev/null || true)
    if [ -n "$stale_containers" ]; then
        echo "$stale_containers" | xargs docker rm -f >/dev/null 2>&1 || true
    fi

    for stale_volume in \
        "${PROJECT_NAME}_minio_data" \
        "${PROJECT_NAME}_mysql_data" \
        "${PROJECT_NAME}_secure_proxy_files"; do
        docker volume rm -f "$stale_volume" >/dev/null 2>&1 || true
    done
}

cleanup_gitignored_fixture_paths() {
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

        if [[ "$trimmed_path" != tests/fixtures/* ]]; then
            continue
        fi

        rm -rf "${PROJECT_ROOT:?}/$trimmed_path" 2>/dev/null || true
    done < "$gitignore_file"
}

cleanup_docker_build_images() {
    local version
    local tag
    local container

    for version in $PHP_VERSIONS; do
        tag="${TAG_PREFIX}:${version}"
        container="${TAG_PREFIX}-${version}"
        docker rm -f "$container" >/dev/null 2>&1 || true
        if docker images -q "$tag" 2>/dev/null | grep -q .; then
            docker rmi "$tag" >/dev/null 2>&1 || true
        fi
    done
}

echo -e "${BLUE}[INFO] Cleanup mode: $MODE${NC}"

if [ "$MODE" = "docker-build" ]; then
    cleanup_docker_build_images
    echo -e "${GREEN}[INFO] Docker build cleanup complete${NC}"
    exit 0
fi

if [ "$MODE" = "stale" ]; then
    cleanup_compose_state "yes"
    echo -e "${GREEN}[INFO] Stale cleanup complete${NC}"
    exit 0
fi

cleanup_compose_state "no"

docker rm -f "${PROJECT_NAME}-noimport-once" >/dev/null 2>&1 || true
docker rm -f "${PROJECT_NAME}-secure-private-once" >/dev/null 2>&1 || true

if docker image inspect test-df-deployment:8.3 >/dev/null 2>&1; then
    docker run --rm \
      -v "$SCRIPT_DIR/fixtures/app:/var/www/html" \
      --user root \
      --entrypoint "" \
      test-df-deployment:8.3 \
      chown -R "$(id -u):$(id -g)" /var/www/html >/dev/null 2>&1 || true
fi

"${DOCKER_COMPOSE[@]}" -p "$PROJECT_NAME" -f "$COMPOSE_FILE_PATH" rm -f >/dev/null 2>&1 || true

test_images=$(docker images -f "dangling=false" --format "{{.Repository}}:{{.Tag}}" | grep "^test-df-deployment" || true)
if [ -n "$test_images" ]; then
    echo "$test_images" | xargs docker rmi >/dev/null 2>&1 || true
fi

cleanup_gitignored_fixture_paths

echo -e "${GREEN}[INFO] Full cleanup complete${NC}"
