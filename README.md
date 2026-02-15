<h1>
  <a href="https://www.drupalforge.org/">
    <img src="drupalforge.svg" alt="Drupal Forge" height="100px" />
  </a>
  <br />
  <br />
  Deployment Image
</h1>

This repository builds a container image for deploying sites to Drupal Forge.
This provides a safe environment to develop, preview, and share changes.

## Overview

The deployment image is built on [devpanel/php](https://github.com/devpanel/php) base images (PHP 8.2 and 8.3) and adds the following deployment capabilities:

1. **Database Import from S3** - Automatically downloads and imports a database dump from an S3 bucket on container startup
2. **File Proxy Configuration** - Retrieves digital assets on-demand from the origin site using:
   - [Stage File Proxy](https://www.drupal.org/project/stage_file_proxy) module (auto-detected and preferred)
   - Apache reverse proxy (fallback for sites without the module)

The initialization runs automatically before Apache starts, ensuring the application is ready immediately.

## Architecture

### Startup Flow

```
Container Start
    ↓
Deployment Entrypoint (deployment-entrypoint.sh)
    ├─→ Bootstrap App (bootstrap-app.sh)
    │   ├─→ Initialize Git submodules recursively
    │   └─→ Run composer install (if composer.json exists)
    │
    ├─→ Database Import (if S3_BUCKET + S3_DATABASE_PATH set)
    │   └─→ Download from S3 → MySQL import
    │
    ├─→ File Proxy Setup (if ORIGIN_URL set)
    │   ├─→ Detect Stage File Proxy module
    │   ├─→ Fall back to Apache proxy if not found
    │   └─→ Configure proxy caching for locally-added assets (setup-cache.sh)
    │
    └─→ Apache Startup (apache-start.sh from base)
        ├─→ Configure templates with environment variables
        ├─→ Load custom PHP config (if present)
        └─→ Start Apache with rewrite rules (+ optional code-server)
```

### Image Inheritance

Extends `devpanel/php:{8.2,8.3}-base` with:
- Application bootstrap script (`bootstrap-app.sh`)
- Database import script (`import-database.sh`)
- Proxy configuration script (`setup-proxy.sh`)
- Deployment entrypoint (`deployment-entrypoint.sh`)
- Apache proxy configuration template with conditional rewrite rules

## Requirements

### The repository and application code

Code is mounted into the container at `$APP_ROOT` (default: `/var/www/html`). 

**DevPanel handles:**
- Cloning the repository from Git
- Checking out the specified branch

**Deployment image handles (on startup):**
- Initializing and updating Git submodules recursively
- Running `composer install` if `composer.json` exists

### The site database

A database dump is stored in an S3 bucket and imported on container startup:
- Must be a valid MySQL dump (`.sql` or `.sql.gz`)
- Stored at the path specified by `S3_DATABASE_PATH`
- Downloaded using AWS credentials (from environment or instance role)
- Automatically skipped if database already has tables

### Digital assets (files)

Digital assets are retrieved on-demand from the origin site using one of two methods:

1. **Stage File Proxy** (preferred if module is installed):
   - Drupal module enables transparent file proxy
   - No additional configuration needed if installed

2. **Apache Reverse Proxy with Conditional Serving** (fallback):
   - Serves local files if they exist at the requested path
   - Proxies to origin only if the file doesn't exist locally
   - Allows users to add/modify files locally that are served directly
   - Works for any paths specified by `FILE_PROXY_PATHS`
   - Useful for sites without Stage File Proxy module

## Environment Variables

### Database Import Configuration

| Variable | Description | Example |
|----------|-------------|---------|
| `S3_BUCKET` | S3 bucket name (required for import) | `my-deployment-bucket` |
| `S3_DATABASE_PATH` | Path to database dump in S3 (required for import) | `dumps/site-prod.sql.gz` |
| `AWS_REGION` | AWS region (optional, default: `us-east-1`) | `us-east-1` |
| `AWS_ACCESS_KEY_ID` | AWS access key (optional, uses instance role if not provided) | - |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key (optional, uses instance role if not provided) | - |

**Database Connection Variables:** `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` are automatically provided by DevPanel and do not need to be specified when deploying on Drupal Forge. They are only required when running the container outside of Drupal Forge.

### File Proxy Configuration

| Variable | Description | Example |
|----------|-------------|---------|
| `ORIGIN_URL` | Origin site URL for file proxy (required to enable proxy) | `https://prod-site.example.com` |
| `FILE_PROXY_PATHS` | Comma-separated paths to proxy (optional, default: `/sites/default/files`) | `/sites/default/files,/config` |
| `USE_STAGE_FILE_PROXY` | Force Stage File Proxy or Apache proxy (`yes`/`no`, optional auto-detect) | `yes` |
| `WEB_ROOT` | Web root path (optional, default: `/var/www/html/web`) | `/var/www/html/web` |

### Conditional File Serving with On-Demand Download

When using Apache reverse proxy (fallback when Stage File Proxy not available), requests are handled intelligently based on file existence:

**How it works:**
1. User requests file at a proxied path (e.g., `/sites/default/files/image.jpg`)
2. Apache checks if the file exists locally
   - **If it exists:** Serves it directly from disk
   - **If it doesn't exist:** Routes to PHP handler for download
3. Handler downloads file from origin to its real path
4. File is now stored at the expected location (e.g., `/var/www/html/web/sites/default/files/image.jpg`)
5. File is served to the user
6. Subsequent requests for the same file:
   - **Always served from disk** (file now exists locally)
7. Users can add/modify files locally at any time—local files always take precedence

**Result:** Origin files are downloaded on first access and saved to their real paths. Users can add new local files anytime. Downloaded files are discoverable and editable in the filesystem.


- `APP_ROOT` - Application root directory
- `PHP_MEMORY_LIMIT` - PHP memory limit
- `PHP_MAX_EXECUTION_TIME` - PHP maximum execution time
- `CODES_ENABLE` - Enable code-server (`yes`/`no`)
- And many more PHP configuration options...

## Usage Examples

### Basic Deployment with Database Import

```bash
docker run \
  -e DB_HOST=mysql \
  -e DB_USER=drupal \
  -e DB_PASSWORD=secret \
  -e DB_NAME=drupaldb \
  -e S3_BUCKET=my-deployments \
  -e S3_DATABASE_PATH=dumps/site.sql.gz \
  -e AWS_ACCESS_KEY_ID=AKIA... \
  -e AWS_SECRET_ACCESS_KEY=... \
  -v /path/to/app:/var/www/html \
  -p 80:80 \
  drupalforge/deployment:8.3
```

**Note:** When deployed on Drupal Forge, database connection variables (`DB_HOST`, `DB_USER`, etc.) are automatically provided by DevPanel.

### Deployment with File Proxy (Stage File Proxy)

```bash
docker run \
  -e DB_HOST=mysql \
  -e DB_USER=drupal \
  -e DB_PASSWORD=secret \
  -e DB_NAME=drupaldb \
  -e S3_BUCKET=my-deployments \
  -e S3_DATABASE_PATH=dumps/site.sql.gz \
  -e ORIGIN_URL=https://prod-site.example.com \
  -v /path/to/app:/var/www/html \
  -p 80:80 \
  drupalforge/deployment:8.3
```

### Deployment with Apache File Proxy

```bash
docker run \
  -e DB_HOST=mysql \
  -e DB_USER=drupal \
  -e DB_PASSWORD=secret \
  -e DB_NAME=drupaldb \
  -e S3_BUCKET=my-deployments \
  -e S3_DATABASE_PATH=dumps/site.sql.gz \
  -e ORIGIN_URL=https://prod-site.example.com \
  -e FILE_PROXY_PATHS=/sites/default/files,/modules/contrib/custom_module/assets \
  -v /path/to/app:/var/www/html \
  -p 80:80 \
  drupalforge/deployment:8.3
```

### Deployment with Code Server Development

```bash
docker run \
  -e CODES_ENABLE=yes \
  -e CODES_AUTH=no \
  -e DB_HOST=mysql \
  -e DB_USER=drupal \
  -e DB_PASSWORD=secret \
  -e DB_NAME=drupaldb \
  -e S3_BUCKET=my-deployments \
  -e S3_DATABASE_PATH=dumps/site.sql.gz \
  -v /path/to/app:/var/www/html \
  -p 80:80 \
  -p 8080:8080 \
  drupalforge/deployment:8.3
```

### Using AWS Instance Role (no credentials needed)

When deployed to AWS EC2/ECS with proper IAM role:

```bash
docker run \
  -e DB_HOST=mysql \
  -e DB_USER=drupal \
  -e DB_PASSWORD=secret \
  -e DB_NAME=drupaldb \
  -e S3_BUCKET=my-deployments \
  -e S3_DATABASE_PATH=dumps/site.sql.gz \
  -v /path/to/app:/var/www/html \
  -p 80:80 \
  drupalforge/deployment:8.3
```

## Available Tags

- `drupalforge/deployment:8.2` - PHP 8.2 base
- `drupalforge/deployment:8.3` - PHP 8.3 base (latest)
- Branch and SHA-based tags available for development/testing

## Build Images

To build locally:

```bash
# Build PHP 8.3 image
docker build --build-arg PHP_VERSION=8.3 -t drupalforge/deployment:8.3 .

# Build PHP 8.2 image
docker build --build-arg PHP_VERSION=8.2 -t drupalforge/deployment:8.2 .
```

## Deployment Workflow

1. **Code Volume:** Application code is mounted at `$APP_ROOT`
2. **Bootstrap Application:** On startup, initialize Git submodules recursively and run composer install if needed
3. **Database Initialization:** Database is imported from S3 (skipped if already populated)
4. **Proxy Configuration:** File proxy configured with conditional rewrite rules (if using Apache proxy)
5. **Apache Start:** Web server starts and application is ready to serve requests
6. **Code Server:** Optional development interface available on port 8080

## Testing

This repository includes a comprehensive test suite to validate all components:

### Unit Tests

```bash
# Run all unit tests
bash tests/unit-test.sh

# Run specific test suite
bash tests/test-bootstrap-app.sh
bash tests/test-import-database.sh
bash tests/test-setup-proxy.sh
bash tests/test-proxy-handler.sh
bash tests/test-dockerfile.sh
```

### Integration Tests

End-to-end testing with Docker Compose validates the complete deployment flow:

```bash
# Run full integration test
bash tests/integration-test.sh
```

This validates:
- Database import from S3 (using MinIO for local testing)
- Application database connectivity
- Git bootstrap and Composer installation
- File proxy setup and configuration
- File proxy downloads from origin server
- Downloaded files persist locally

**Setup:** The integration test automatically:
1. Builds the deployment image
2. Starts MinIO, MySQL, and a mock origin server
3. Runs the deployment container with full initialization
4. Executes 11 validation checks
5. Cleans up resources

See [INTEGRATION_TESTING.md](tests/INTEGRATION_TESTING.md) for detailed manual testing instructions.

### Test Coverage

- **Unit Tests**: 40+ individual tests covering all scripts and configuration
- **Integration Tests**: 11 end-to-end validation checks
- **CI/CD**: Automated tests on every PR and push to main branch
  - Tests run automatically on pull requests that are ready for review
  - Draft pull requests require manual approval before tests run
  - When a draft PR is marked as ready for review, any pending workflow runs waiting for approval are automatically canceled

See `.github/workflows/tests.yml` for details.

#### Setting Up Draft PR Approval (Optional)

To require manual approval for tests on draft PRs, configure GitHub environments:

1. Go to repository **Settings** → **Environments**
2. Create environment named `draft-pr-approval`
3. Enable **Required reviewers** protection rule
4. Add reviewers who can approve test runs on draft PRs
5. Create environment named `auto-approve` with no protection rules

Without these environments configured, the workflow will still function but won't enforce approval requirements.

## Troubleshooting

### Database Import Fails

Check logs for:
- S3 bucket/path accessibility (AWS credentials, permissions)
- MySQL connectivity (host, port, credentials)
- Database file integrity

### File Proxy Not Working

- **Stage File Proxy:** Verify module is installed at `modules/contrib/stage_file_proxy`
- **Apache Proxy:** Check `FILE_PROXY_PATHS` matches actual file locations in your app
- **Origin URL:** Ensure `ORIGIN_URL` is accessible from container

### Container Starts But No Deployment

Optional features (database import, file proxy) gracefully skip if not configured. Only required variables are `APP_ROOT` and the database/proxy info matched to your setup.

