#!/bin/bash
# Build script that automatically extracts and uses the base image's CMD
set -e

PHP_VERSION="${1:-8.3}"

echo "======================================"
echo "Building Drupal Forge Deployment Image"
echo "======================================"
echo ""

# Extract CMD from base image
echo "[1/2] Extracting CMD from base image..."
BASE_CMD=$(./extract-base-cmd.sh "${PHP_VERSION}")
echo "      Base CMD: ${BASE_CMD}"
echo ""

# Build the image
echo "[2/2] Building image..."
docker build \
  --build-arg PHP_VERSION="${PHP_VERSION}" \
  --build-arg BASE_CMD="${BASE_CMD}" \
  -t "drupalforge/deployment:${PHP_VERSION}" \
  .

echo ""
echo "======================================"
echo "✓ Build complete!"
echo "======================================"
echo ""
echo "Image: drupalforge/deployment:${PHP_VERSION}"
echo "Base CMD: ${BASE_CMD}"
echo ""
