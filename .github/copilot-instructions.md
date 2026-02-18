# Copilot Instructions for Drupal Forge Deployment

## Project Overview

This repository builds a container image for deploying Drupal sites to Drupal Forge. It provides a safe environment to develop, preview, and share changes. The deployment image is built on [devpanel/php](https://github.com/devpanel/php) base images (PHP 8.2 and 8.3) and adds deployment capabilities including database import from S3 and file proxy configuration.

## Technology Stack

- **Base Image**: devpanel/php (PHP 8.2 and 8.3)
- **Web Server**: Apache with mod_rewrite, mod_proxy
- **Languages**: Bash (shell scripts), PHP (proxy handler)
- **Target Application**: Drupal CMS
- **Storage**: AWS S3 for database dumps
- **Testing**: Bash unit tests, Docker Compose integration tests
- **CI/CD**: GitHub Actions workflows

## Repository Structure

```
.
├── .github/               # GitHub configuration and workflows
│   └── workflows/        # CI/CD workflow definitions
├── config/               # Apache and configuration files
├── scripts/              # Deployment and startup scripts (Bash)
│   ├── bootstrap-app.sh          # Initialize Git submodules and Composer
│   ├── deployment-entrypoint.sh  # Container entrypoint orchestrator
│   ├── import-database.sh        # S3 database import
│   └── setup-proxy.sh            # File proxy configuration
├── tests/                # Test suite
│   ├── fixtures/         # Test fixtures and mock data
│   ├── test-*.sh        # Individual unit test scripts
│   ├── unit-test.sh     # Unit test runner
│   └── integration-test.sh  # Integration test runner
├── proxy-handler.php     # PHP handler for file downloads
├── Dockerfile           # Multi-stage Docker build
└── README.md            # Comprehensive documentation
```

## Key Concepts

### Startup Flow
1. Container starts with `deployment-entrypoint.sh`
2. Bootstrap app: Initialize Git submodules and run composer install
3. Database import: Download from S3 and import to MySQL (if configured)
4. Proxy setup: Configure Stage File Proxy or Apache reverse proxy (if configured)
5. Apache starts and serves the application

### File Proxy Strategy
The image supports two methods for retrieving digital assets on-demand:
1. **Stage File Proxy** (preferred): Drupal module for transparent file proxying
2. **Apache Reverse Proxy** (fallback): Conditional serving with PHP handler that downloads files to their expected paths

## Coding Standards and Conventions

### Bash Scripts
- Use `#!/bin/bash` shebang
- Enable strict mode: `set -e` (exit on error)
- Use meaningful variable names in UPPER_CASE for environment variables
- Quote all variable expansions: `"${VAR}"`
- Add comments for complex logic
- Check for required environment variables before using them
- Use `echo "[INFO]"`, `echo "[ERROR]"`, etc. for logging
- Make scripts executable (`chmod +x`)

### PHP Code
- Follow PSR-12 coding standards
- Use meaningful variable names in camelCase
- Add comments for complex logic
- Validate input parameters
- Handle errors gracefully with proper error messages

### Docker
- Use ARG for build-time variables
- Use ENV for runtime variables
- Switch to non-root user for runtime operations
- Use ENTRYPOINT for required initialization
- Add descriptive labels for image metadata
- Multi-line RUN commands should use `&&` and `\` for readability

### Apache Configuration
- Use descriptive comments
- Group related directives together
- Use RewriteCond/RewriteRule for conditional file serving
- Enable required modules explicitly

## Testing Requirements

### Before Making Changes
Always run tests before making code changes to understand any existing failures:
```bash
# Run all unit tests
bash tests/unit-test.sh

# Run specific unit test
bash tests/test-bootstrap-app.sh
bash tests/test-import-database.sh
bash tests/test-setup-proxy.sh
bash tests/test-proxy-handler.sh
bash tests/test-dockerfile.sh
```

### After Making Changes
Always test your changes:
```bash
# Unit tests (fast, run frequently)
bash tests/unit-test.sh

# Integration tests (slower, comprehensive)
bash tests/integration-test.sh
```

### Writing Tests
- Unit tests go in `tests/test-<component>.sh`
- Use `assert_equals`, `assert_contains`, `assert_file_exists` helpers
- Test both success and failure cases
- Mock external dependencies (S3, databases) in unit tests
- Integration tests should validate end-to-end workflows

## Building and Testing

### Build Images
```bash
# Build PHP 8.3 image
docker build --build-arg PHP_VERSION=8.3 -t drupalforge/deployment:8.3 .

# Build PHP 8.2 image
docker build --build-arg PHP_VERSION=8.2 -t drupalforge/deployment:8.2 .
```

### Test Locally
```bash
# Run unit tests
bash tests/unit-test.sh

# Run integration tests (requires Docker Compose)
bash tests/integration-test.sh

# Run all tests
bash tests/run-all-tests.sh
```

## Environment Variables

Key environment variables used by the deployment scripts:

### Database Import
- `S3_BUCKET`: S3 bucket name (required for import)
- `S3_DATABASE_PATH`: Path to database dump in S3 (required for import)
- `AWS_REGION`: AWS region (default: us-east-1)
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`: AWS credentials (optional if using instance role)
- `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`: Database connection parameters

### File Proxy
- `ORIGIN_URL`: Origin site URL for file proxy (required to enable proxy)
- `FILE_PROXY_PATHS`: Comma-separated paths to proxy (default: /sites/default/files)
- `USE_STAGE_FILE_PROXY`: Force Stage File Proxy or Apache proxy (yes/no, auto-detect by default)
- `WEB_ROOT`: Web root path (default: /var/www/html/web)

### Application
- `APP_ROOT`: Application root directory (default: /var/www/html)

## Important Notes

### Security
- Never commit AWS credentials or secrets to the repository
- Use environment variables for sensitive data
- Validate and sanitize all external inputs
- Follow principle of least privilege for file permissions
- Switch to non-root user for runtime operations

### Error Handling
- Scripts should exit with non-zero status on errors (`set -e`)
- Provide clear error messages that help users diagnose issues
- Log important steps with `[INFO]` prefix
- Log errors with `[ERROR]` prefix
- Gracefully skip optional features when not configured

### Documentation
- Update README.md when adding new features or changing behavior
- Add comments to complex code sections
- Document all environment variables
- Provide usage examples for new features

### Git Workflow
- Keep commits focused and atomic
- Write clear, descriptive commit messages
- Test changes before committing
- Run both unit and integration tests before pushing

## CI/CD Workflows

The repository uses GitHub Actions for automated testing:
- **tests.yml**: Runs on pull requests and pushes to main
  - Executes unit tests and Docker builds
  - Draft PRs: Workflow runs require approval (enforced by GitHub, prevents automatic execution)
  - Ready PRs: Runs execute without approval and cancel previous runs awaiting approval
- **auto-approve-copilot.yml**: Auto-approves workflow runs from Copilot bot
  - Allows workflows to run on draft PRs without manual approval
  - Uses `pull_request_target` with `actions: write` permission
  - Alternative to marking PR ready or manually approving
- **docker-publish-images.yml**: Builds and publishes Docker images for multiple PHP versions
- **docker-publish-image.yml**: Builds and publishes a single Docker image (deprecated)

## Common Tasks

### Adding a New Script
1. Create the script in `scripts/` directory
2. Make it executable: `chmod +x scripts/new-script.sh`
3. Add Bash strict mode: `set -e`
4. Copy to image in Dockerfile
5. Create corresponding unit test in `tests/test-new-script.sh`
6. Update README.md documentation
7. Run tests to validate

### Modifying Proxy Behavior
1. Update `scripts/setup-proxy.sh` for configuration logic
2. Update `proxy-handler.php` for download/serving logic
3. Update `config/apache-proxy.conf` for Apache rules
4. Update corresponding tests
5. Run integration tests to validate end-to-end

### Updating Base Image Version
1. Modify `FROM` in Dockerfile
2. Test build process
3. Run full test suite
4. Update documentation if new features are available

## Best Practices

- **Make minimal changes**: Only change what's necessary to solve the problem
- **Test thoroughly**: Run unit tests after every change, integration tests before finalizing
- **Document your changes**: Update README and comments as needed
- **Follow existing patterns**: Match the style and structure of existing code
- **Handle edge cases**: Consider what happens when optional configuration is missing
- **Be defensive**: Check for required variables and files before using them
- **Keep it simple**: Prefer clear, straightforward solutions over clever ones
