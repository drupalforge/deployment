# Integration Testing Guide

This directory contains fixtures and scripts for integration testing the deployment image.

## What's Included

- **docker-compose.test.yml** - Complete test environment orchestration
- **integration-test.sh** - Full validation script
- **fixtures/**
  - `app/` - Drupal app fixture used by bootstrap and runtime checks
  - `test-database.sql.gz` - Drupal database dump used for import/install-state testing
  - `origin-files/` - Mock origin server files

## Services

The test environment includes:

1. **MinIO** - S3-compatible object storage (replaces S3 for testing)
2. **MySQL** - Database server
3. **Origin Server** - Python HTTP server simulating the production origin
4. **Deployment Container** - The built image being tested

## Running Integration Tests

### Prerequisites

- Docker and Docker Compose installed
- Outbound network access for GitHub and Packagist (first-run fixture initialization)

### Run Complete Test Suite

```bash
cd tests
bash integration-test.sh
```

This will:

1. Start all services.
2. Build the deployment image.
3. Initialize `fixtures/app` in compose when fixture root files are missing.
4. Run 18 validation tests covering:

   - Database import from S3/MinIO.
   - Application connectivity to database.
   - Drupal install-state detection (homepage must not redirect to installer).
   - No-import installer flow skips database setup when DevPanel settings are included (validated via one-off container using the same built image).
   - Private file path creation and ownership alignment with Apache runtime user/group.
   - Secure-mode private path ownership alignment with default Apache `www-data`.
   - One-off validation containers run on the host's native Docker platform (no forced amd64).
   - Apache proxy rewrites are injected into the active virtual host scope so missing-file requests are intercepted before Drupal's front controller fallback.
   - Bootstrap (Git submodules, Composer).
   - File proxy setup.
   - File download from origin and local persistence.

5. Clean up resources.

### Manual Testing

If you want to manually test components:

```bash
# Start services
cd tests
docker-compose -f docker-compose.test.yml up -d

# Wait for services to be ready
sleep 30

# Access the application
docker-compose -f docker-compose.test.yml exec deployment curl http://localhost/

# Check if file was proxied
docker-compose -f docker-compose.test.yml exec deployment curl http://localhost/sites/default/files/test-image.txt

# View deployment logs
docker-compose -f docker-compose.test.yml logs -f deployment

# Stop services
docker-compose -f docker-compose.test.yml down

# Full cleanup (matches integration-test.sh cleanup behavior)
bash cleanup-test-environment.sh --mode full
```

### Manual-only deployment environment overrides

For local-only experiments, use an opt-in compose overlay that applies env-file
overrides to `app-fixture-prepare` and `deployment`:

```bash
cd tests
docker compose -f docker-compose.test.yml -f docker-compose.manual.yml up -d
```

Create `tests/.env.manual` with only the values you want to override. The
overlay keeps CI and scripted runs unchanged because it is only active when you
explicitly include `docker-compose.manual.yml`.

Shared defaults are loaded from `tests/.env.shared` for both test and manual
runs.

`tests/.env.test` is layered only by `docker-compose.test.yml` and sets
`AWS_S3_ENDPOINT` for MinIO-backed integration tests.

`docker-compose.manual.yml` uses `!override` so manual runs load
`tests/.env.shared` plus `tests/.env.manual` (and do not inherit
`tests/.env.test`).

During manual testing, `AWS_S3_ENDPOINT` is only set if you add it to
`tests/.env.manual`.

To change the fixture repository/branch used by `app-fixture-prepare`, set
`DP_REPO_BRANCH` in `tests/.env.manual`. Example:

```bash
cat > tests/.env.manual <<'EOF'
DP_REPO_BRANCH=https://github.com/drupal/recommended-project/tree/11.x
# DP_REPO_BRANCH=https://gitlab.com/devpanel-vn/drupal-forge/-/tree/staging
EOF

cd tests
docker compose -f docker-compose.test.yml -f docker-compose.manual.yml up -d
```

The compose stack runs a one-shot `app-fixture-prepare` service before the deployment containers start. It bootstraps `fixtures/app` from `drupal/recommended-project` 11.x when root files are missing, ensures `settings.php` exists, and fixes ownership/write permissions so manual startup matches the behavior of `integration-test.sh` on macOS and Linux.

Because of this first-run initialization, manual `up -d` can take longer and requires outbound network access for GitHub/Packagist.

### Shared Cleanup Script

Use `cleanup-test-environment.sh` to reuse the same cleanup logic in automated
and manual workflows:

```bash
cd tests

# Pre-run stale cleanup (containers/volumes)
bash cleanup-test-environment.sh --mode stale

# Post-run full cleanup (stale cleanup + fixture/image cleanup)
bash cleanup-test-environment.sh --mode full

# Docker build image/container cleanup (used by docker-build-test.sh)
bash cleanup-test-environment.sh --mode docker-build
```

## Test Coverage

The integration test validates:

✓ Database import from S3 (via MinIO)
✓ Drupal home page does not redirect to installer
✓ Application database connectivity
✓ Git initialization during bootstrap
✓ Composer.json present
✓ Rewrite rules generated
✓ PHP proxy handler deployed
✓ Origin server connectivity
✓ File proxy downloads from origin
✓ Proxied files persist locally
✓ Apache proxy rewrites preserve the original request path when dispatching to the handler alias
✓ S3/MinIO connectivity
✓ Secure-mode file proxy download path works with default Apache `www-data`
✓ DevPanel settings template exists in container
✓ DevPanel include injection into `settings.php` is idempotent
✓ Secure-mode private path is owned by default Apache user/group (`www-data`)
✓ Private file path exists and is owned by the Apache runtime user/group
✓ No-import installer flow skips database setup when DevPanel settings are included

## Troubleshooting

### Services won't start

```bash
# Check Docker resources
docker system df

# Clean up unused resources
docker system prune -a
```

### Tests timeout

```bash
# Manually check service status
docker-compose -f docker-compose.test.yml ps

# View logs
docker-compose -f docker-compose.test.yml logs deployment
```

### MinIO connection issues

```bash
# Check if MinIO is running and bucket exists
docker-compose -f docker-compose.test.yml exec minio mc ls minio/test-deployments
```

### Database import didn't happen

```bash
# Check MySQL
docker-compose -f docker-compose.test.yml exec mysql mysql -uroot -proot_password -Ddrupaldb -e "SHOW TABLES;"
```

## Environment Variables Used

The test deployment container receives:

```text
DB_HOST=mysql
DB_USER=drupal
DB_PASSWORD=drupal_password
DB_NAME=drupaldb
S3_BUCKET=test-deployments
S3_DATABASE_PATH=test-db.sql.gz
AWS_ACCESS_KEY_ID=minioadmin
AWS_SECRET_ACCESS_KEY=minioadmin
AWS_S3_ENDPOINT=http://minio:9000
ORIGIN_URL=http://origin-server:8000
FILE_PROXY_PATHS=/sites/default/files
WEB_ROOT=/var/www/html/web
APACHE_RUN_USER=www
APACHE_RUN_GROUP=www
```

### Apache Less Secure Mode (Test Environment Only)

The test environment sets `APACHE_RUN_USER=www` and `APACHE_RUN_GROUP=www` to run Apache as the container user (UID 1000) instead of the default `www-data` (UID 33). This eliminates file permission mismatches in tests:

- **Container user**: `www` (UID 1000)
- **Apache user**: `www` (UID 1000) ← same as container
- **Result**: No permission issues when Apache writes files

This is called "less secure mode" because Apache runs with the same privileges as the application user. While appropriate for testing, production deployments should use the default `www-data` user for better security isolation.

## Adding More Tests

To add additional integration tests, edit `integration-test.sh` and add new `run_test` calls following the existing pattern:

```bash
run_test "Description of what's being tested" \
    "command that returns 0 if test passes"
```
