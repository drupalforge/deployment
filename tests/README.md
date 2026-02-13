# Test Suite Documentation

This directory contains different types of tests for the Drupal Forge deployment image.

## Quick Reference

| Test Type | Builds Docker Image? | Runtime | When to Use |
|-----------|---------------------|---------|-------------|
| Unit Tests (`test-*.sh`) | ❌ No | < 1 sec | Quick syntax validation |
| CI Docker Build | ✅ Yes | ~1 min | Automated CI checks |
| Integration Test | ✅ Yes | ~3 min | Full E2E + build validation |

**Key Point**: Only integration tests and CI docker-build actually compile the Dockerfile. Running `bash run-all-tests.sh` alone does NOT catch Docker build errors!

## Test Types

### 1. Unit Tests (Syntax/Pattern Checks)

**Files**: `test-*.sh` scripts  
**Run via**: `bash run-all-tests.sh`  
**Purpose**: Validate Dockerfile syntax and script structure without building images

These tests use `grep` and file inspection to check:
- Dockerfile contains required directives
- Scripts have proper permissions
- Configuration files exist
- Code patterns are present

**Important**: These tests do NOT build Docker images. They only check the text content of files.

Example:
```bash
# This checks if the text "a2enmod proxy" exists in the Dockerfile
if grep -q "a2enmod.*proxy" "$DOCKERFILE"; then
    echo "✓ Enables mod_proxy"
fi
```

### 2. Docker Build Tests (CI)

**Location**: `.github/workflows/tests.yml` (docker-build job)  
**Purpose**: Build Docker images to validate they compile successfully

These tests:
- Build images for PHP 8.2 and 8.3
- Validate that all RUN commands execute successfully
- Catch runtime issues like permission errors
- Use GitHub Actions' `docker/build-push-action`
- Run automatically in CI on every push

### 3. Integration Tests (Build + E2E)

**File**: `integration-test.sh`  
**Run via**: `bash integration-test.sh` (from tests/ directory)  
**Purpose**: Build the Docker image AND perform end-to-end validation

**Important**: Integration tests DO build the Docker image using docker-compose!

These tests:
- **Build the deployment Docker image** (PHP 8.3) via docker-compose
- Start complete environment (MySQL, MinIO, origin server)
- Test database imports from S3/MinIO
- Validate application bootstrapping
- Test file proxy functionality
- Simulate real deployment scenarios

See [INTEGRATION_TESTING.md](./INTEGRATION_TESTING.md) for details.

## Running Tests Locally

### Quick Validation (Unit Tests Only)
```bash
cd tests
bash run-all-tests.sh
```
✅ Fast (< 1 second)  
⚠️ Does not build Docker images

### Build Validation (Manual Docker Build)
```bash
# Build and test PHP 8.3 image
docker build --build-arg PHP_VERSION=8.3 -t test:8.3 .

# Build and test PHP 8.2 image
docker build --build-arg PHP_VERSION=8.2 -t test:8.2 .
```
✅ Validates actual Docker build  
⏱️ Slower (~30-60 seconds per image)

### Full Integration Test (Build + E2E)
```bash
cd tests
bash integration-test.sh
```
✅ **Builds Docker image** (PHP 8.3) via docker-compose  
✅ Complete end-to-end validation with real services  
⏱️ Slowest (~2-5 minutes)

**Note**: Integration tests automatically build the Docker image using `docker-compose up --build`. This is the most comprehensive local test option.

## CI Workflow

In CI, tests run in this order:

1. **unit-tests** job: Runs all `test-*.sh` scripts (grep-based validation)
2. **docker-build** job: Builds Docker images for PHP 8.2 and 8.3

Both must pass for the workflow to succeed.

**Note**: Integration tests are NOT run in CI by default (they require docker-compose and take longer). They should be run manually during development or as part of release validation.

## Common Gotchas

### "Tests passed locally but failed in CI"

If you ran `bash run-all-tests.sh` locally, you only ran the **unit tests** (syntax checks). The CI also runs **docker-build** which actually compiles the Dockerfile.

**Solution**: Test Docker builds locally before pushing:
```bash
# Option 1: Manual build (faster, tests just compilation)
docker build --build-arg PHP_VERSION=8.3 -t test:latest .

# Option 2: Integration test (slower, tests compilation + functionality)
cd tests && bash integration-test.sh
```

### "Docker build works locally but fails in CI"

This can happen due to:
- Different Docker versions
- Different buildx configurations  
- Different permission models
- Cached layers hiding issues

**Solution**: Use `--no-cache` flag to ensure clean build:
```bash
docker build --no-cache --build-arg PHP_VERSION=8.3 -t test:latest .
```

### "Integration tests fail to start"

Integration tests require:
- Docker Compose installed
- Sufficient Docker resources (memory, disk)
- Available ports (80, 3306, 8000, 9000, 9001)

**Solution**: Check resources and port availability:
```bash
docker system df  # Check disk usage
docker system prune -a  # Clean up if needed
lsof -i :80  # Check if port 80 is available
```

## Test Development Guidelines

When adding new tests:

1. **Unit tests** - Add to `tests/test-*.sh` for quick syntax validation
2. **Build validation** - Update `.github/workflows/tests.yml` if build process changes
3. **Integration tests** - Update `integration-test.sh` for functional features

Keep tests fast, focused, and independent.
