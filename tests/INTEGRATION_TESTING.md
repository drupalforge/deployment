# Integration Testing Guide

This directory contains fixtures and scripts for integration testing the deployment image.

## What's Included

- **docker-compose.test.yml** - Complete test environment orchestration
- **integration-test.sh** - Full validation script
- **fixtures/**
  - `app/` - Drupal app fixture used by bootstrap and runtime checks
  - `test-database.sql` - Drupal database dump used for import/install-state testing
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
- Git (for initializing the test app repository)

### Run Complete Test Suite

```bash
cd tests
bash integration-test.sh
```

This will:
1. Start all services
2. Build the deployment image
3. Run 15 validation tests covering:
   - Database import from S3/MinIO
   - Application connectivity to database
  - Drupal install-state detection
   - Bootstrap (Git submodules, Composer)
   - File proxy setup
   - File download from origin and local persistence
4. Clean up resources

### Manual Testing

If you want to manually test components:

```bash
# Start services
cd tests
docker-compose -f docker-compose.test.yml up -d

# Wait for services to be ready
sleep 30

# Access the application
docker-compose -f docker-compose.test.yml exec deployment curl http://localhost/index.php

# Check if file was proxied
docker-compose -f docker-compose.test.yml exec deployment curl http://localhost/sites/default/files/test-image.txt

# View deployment logs
docker-compose -f docker-compose.test.yml logs -f deployment

# Stop services
docker-compose -f docker-compose.test.yml down
```

## Test Coverage

The integration test validates:

✓ Database import from S3 (via MinIO)
✓ Application database connectivity
✓ Application web access
✓ Git initialization during bootstrap
✓ Composer.json present
✓ Rewrite rules generated
✓ PHP proxy handler deployed
✓ Origin server connectivity
✓ File proxy downloads from origin
✓ Proxied files persist locally
✓ S3/MinIO connectivity
✓ DevPanel settings template and include injection

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

```
DB_HOST=mysql
DB_USER=drupal
DB_PASSWORD=drupal_password
DB_NAME=drupaldb
S3_BUCKET=test-deployments
S3_DATABASE_PATH=test-db.sql
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
