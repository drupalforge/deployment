#!/bin/bash
# Extract CMD from base image and format for Dockerfile
set -e

PHP_VERSION="${1:-8.3}"
BASE_IMAGE="devpanel/php:${PHP_VERSION}-base"

echo "Extracting CMD from ${BASE_IMAGE}..." >&2

# Pull the base image if not present
docker pull "${BASE_IMAGE}" >/dev/null 2>&1

# Extract CMD as JSON array
CMD_JSON=$(docker inspect "${BASE_IMAGE}" --format='{{json .Config.Cmd}}')

# Parse and format the CMD - convert JSON array to space-separated string
# This handles the JSON array format like ["sudo","-E","/bin/bash","/scripts/apache-start.sh"]
CMD_STRING=$(echo "${CMD_JSON}" | jq -r 'join(" ")')

echo "${CMD_STRING}"
