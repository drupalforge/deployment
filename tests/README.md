# Test Suite Documentation

This directory contains different types of tests for the Drupal Forge deployment image.

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

### 2. Docker Build Tests

**Location**: `.github/workflows/tests.yml` (docker-build job)  
**Purpose**: Actually build Docker images to validate they compile successfully

These tests:
- Build images for PHP 8.2 and 8.3
- Validate that all RUN commands execute successfully
- Catch runtime issues like permission errors
- Use GitHub Actions' `docker/build-push-action`

### 3. Integration Tests

**File**: `integration-test.sh`  
**Purpose**: End-to-end validation of the deployed container

These tests:
- Start complete environment with docker-compose
- Test database imports from S3/MinIO
- Validate application bootstrapping
- Test file proxy functionality
- Simulate real deployment scenarios

See [INTEGRATION_TESTING.md](./INTEGRATION_TESTING.md) for details.

## Running Tests Locally

### Quick Validation (Unit Tests)
```bash
cd tests
bash run-all-tests.sh
```
✅ Fast (< 1 second)  
⚠️ Does not build Docker images

### Build Validation (Docker Build)
```bash
# Build and test PHP 8.3 image
docker build --build-arg PHP_VERSION=8.3 -t test:8.3 .

# Build and test PHP 8.2 image
docker build --build-arg PHP_VERSION=8.2 -t test:8.2 .
```
✅ Validates actual Docker build  
⏱️ Slower (~30-60 seconds per image)

### Full Integration Test
```bash
cd tests
bash integration-test.sh
```
✅ Complete end-to-end validation  
⏱️ Slowest (~2-5 minutes)

## CI Workflow

In CI, tests run in this order:

1. **unit-tests** job: Runs all `test-*.sh` scripts
2. **docker-build** job: Builds Docker images for PHP 8.2 and 8.3

Both must pass for the workflow to succeed.

## Common Gotchas

### "Tests passed locally but failed in CI"

If you ran `bash run-all-tests.sh` locally, you only ran the **unit tests** (syntax checks). The CI also runs **docker-build** which actually compiles the Dockerfile.

**Solution**: Always test Docker builds locally before pushing:
```bash
docker build --build-arg PHP_VERSION=8.3 -t test:latest .
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

## Test Development Guidelines

When adding new tests:

1. **Unit tests** - Add to `tests/test-*.sh` for quick syntax validation
2. **Build validation** - Update `.github/workflows/tests.yml` if build process changes
3. **Integration tests** - Update `integration-test.sh` for functional features

Keep tests fast, focused, and independent.
