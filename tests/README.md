# Test Suite Documentation

This directory contains different types of tests for the Drupal Forge deployment image.

## Test Commands

### Run All Tests (Recommended)
```bash
cd tests
bash run-all-tests.sh
```
Runs unit tests, Docker builds, and integration tests in sequence. **Use this before pushing.**

### Run Specific Test Types
```bash
# Unit tests only (fast, ~1 second)
bash unit-test.sh

# Docker build tests only (~1-2 minutes)
bash docker-build-test.sh

# Integration tests only (~3-5 minutes)
bash integration-test.sh
```

### Git Hooks (Automated)
```bash
# Set up pre-push hook to run tests automatically
git config core.hooksPath .githooks
```
See [.githooks/README.md](../.githooks/README.md) for details.

## Quick Reference

| Test Type | Builds Docker Image? | Runtime | Cleanup | Command |
|-----------|---------------------|---------|---------|---------|
| Unit Tests | ❌ No | < 1 sec | N/A | `unit-test.sh` |
| Docker Build | ✅ Yes | ~1-2 min | ✅ Auto | `docker-build-test.sh` |
| Integration Test | ✅ Yes | ~3-5 min | ✅ Auto | `integration-test.sh` |
| **All Tests** | ✅ Yes | ~5-8 min | ✅ Auto | `run-all-tests.sh` |

**All tests automatically clean up after themselves** - no leftover Docker images or containers.

## Test Types

### 1. Unit Tests (Syntax/Pattern Checks)

**Files**: `test-*.sh` scripts  
**Run via**: `bash unit-test.sh`  
**Purpose**: Validate Dockerfile syntax and script structure without building images

These tests use `grep` and file inspection to check:
- Dockerfile contains required directives
- Scripts have proper permissions
- Configuration files exist
- Code patterns are present
- YAML files follow consistent formatting (via yamllint)

**Important**: Unit tests do NOT build Docker images. They only check the text content of files.

Example:
```bash
# This checks if the text "a2enmod proxy" exists in the Dockerfile
if grep -q "a2enmod.*proxy" "$DOCKERFILE"; then
    echo "✓ Enables mod_proxy"
fi
```

### 2. Docker Build Tests (CI)

**File**: `docker-build-test.sh`  
**Run via**: `bash docker-build-test.sh` (from tests/ directory)  
**Purpose**: Build Docker images to validate they compile successfully

These tests:
- Build images for PHP 8.2 and 8.3
- Validate that all RUN commands execute successfully
- Catch runtime issues like permission errors
- Verify user configuration is correct
- Verify BASE_CMD environment variable is set
- **Test CMD execution**: Container runs with default CMD, Apache starts, command override works
- Use automatic cleanup of test images
- Run in CI on every push

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

### Recommended: Run All Tests
```bash
cd tests
bash run-all-tests.sh
```
✅ Runs unit tests, Docker builds, and integration tests  
✅ Automatic cleanup of all test artifacts  
✅ Clear pass/fail summary  
⏱️ Takes ~5-8 minutes

**Use this command before pushing to catch all issues.**

### Quick: Unit Tests Only
```bash
cd tests
bash unit-test.sh
```
✅ Fast (< 1 second)  
⚠️ Does not build Docker images  
⚠️ May miss Docker build errors

### Medium: Docker Build Tests
```bash
cd tests
bash docker-build-test.sh
```
✅ Tests PHP 8.2 and 8.3 builds  
✅ Verifies user configuration and permissions  
✅ Automatic cleanup of test images  
⏱️ Takes ~1-2 minutes

### Comprehensive: Integration Tests
```bash
cd tests
bash integration-test.sh
```
✅ Builds Docker image via docker-compose  
✅ Complete end-to-end validation with real services  
✅ Automatic cleanup of containers and images  
⏱️ Takes ~3-5 minutes

## Automated Testing with Git Hooks

Set up the pre-push hook to automatically run tests before pushing:

```bash
git config core.hooksPath .githooks
```

The hook will:
- Detect which files changed
- Run only relevant tests (faster)
- Block push if tests fail
- Clean up automatically

See [.githooks/README.md](../.githooks/README.md) for details.

## CI Workflow

In CI, tests run in this order:

1. **unit-tests** job: Runs all `test-*.sh` scripts (grep-based validation)
2. **docker-build** job: Builds Docker images for PHP 8.2 and 8.3

Both must pass for the workflow to succeed.

**Note**: Integration tests are NOT run in CI by default (they require docker-compose and take longer). They should be run manually during development or as part of release validation.

## Common Gotchas

### "Tests passed locally but failed in CI"

If you ran `bash unit-test.sh` locally, you only ran the **unit tests** (syntax checks). The CI also runs **docker-build** which actually compiles the Dockerfile.

**Solution**: Test Docker builds locally before pushing:
```bash
# Option 1: Manual build (faster, tests just compilation)
docker build --build-arg PHP_VERSION=8.3 -t test-df-deployment:8.3 .

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
docker build --no-cache --build-arg PHP_VERSION=8.3 -t test-df-deployment:8.3 .
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

### "Sudo-dependent tests are skipped or flaky in longer runs"

Sudo-dependent checks can skip if non-interactive credentials are not active at the moment they execute.

**Solutions:**
- Re-authenticate before running tests:
    ```bash
    sudo -v
    cd tests && bash unit-test.sh
    ```
- Verify non-interactive sudo is active:
    ```bash
    sudo -n true && echo "sudo active"
    ```
- Keep sudo-dependent tests first in each suite, ordered by expected runtime (shortest to longest), to reduce credential-age risk before privileged checks run.
- If running from hooks or scripts, ensure an interactive TTY is available when a password prompt is needed.

## Test Development Guidelines

When adding new tests:

1. **Unit tests** - Add to `tests/test-*.sh` for quick syntax validation
2. **Build validation** - Update `.github/workflows/tests.yml` if build process changes
3. **Integration tests** - Update `integration-test.sh` for functional features

Keep tests fast, focused, and independent.

### YAML Linting

The test suite includes YAML linting via `yamllint` to ensure consistent formatting across all YAML files (workflows, docker-compose, etc.).

**Configuration**: `.yamllint` at repository root

**To fix linting errors**:
```bash
# Check which files have issues
yamllint .github/workflows/*.yml tests/*.yml

# Common fixes:
# - Remove trailing whitespace
# - Use 2-space indentation
# - Keep lines under 120 characters
```

**Requirements**: Install yamllint if not available:
```bash
pip install yamllint
```
