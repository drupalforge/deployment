#!/bin/bash
# Deployment Entrypoint
# This script runs deployment setup tasks before executing the main command:
# 1. Fix file ownership for mounted volumes (using sudo if needed)
# 2. Bootstrap application (Git submodules, composer install)
# 3. Import database from S3 (if configured)
# 4. Configure file proxy (if configured)
# 5. Execute the provided command (defaults to Apache startup)

set -e

# Function to log messages
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [DEPLOYMENT] $*"
}

log "Starting Drupal Forge deployment initialization"
log "Entrypoint: $0"

BOOTSTRAP_REQUIRED="${BOOTSTRAP_REQUIRED:-yes}"

# Fix file ownership if APP_ROOT is mounted and we have sudo access
APP_ROOT="${APP_ROOT:-/var/www/html}"
WEB_ROOT="${WEB_ROOT:-$APP_ROOT/web}"
if [ -d "$APP_ROOT" ]; then
  # Check if we can use sudo to fix ownership (for mounted volumes with wrong ownership)
  if sudo -n chown --version &>/dev/null; then
    log "Fixing ownership of $APP_ROOT (if needed)..."
    # Only change ownership if we're not already the owner
    current_user=$(id -un)
    owner=$(stat -c '%U' "$APP_ROOT" 2>/dev/null || echo "$current_user")
    if [ "$owner" != "$current_user" ]; then
      sudo chown -R "$current_user:$current_user" "$APP_ROOT" 2>/dev/null || true
      log "Ownership fixed for mounted volume"
    fi
  fi
fi

# Bootstrap application code
log "Bootstrapping application (submodules, composer)..."
if /usr/local/bin/bootstrap-app; then
  log "Application bootstrap completed"
else
  if [ "$BOOTSTRAP_REQUIRED" = "yes" ] || [ "$BOOTSTRAP_REQUIRED" = "true" ] || [ "$BOOTSTRAP_REQUIRED" = "1" ]; then
    log "Application bootstrap failed and BOOTSTRAP_REQUIRED=$BOOTSTRAP_REQUIRED; exiting"
    exit 1
  fi
  log "Application bootstrap failed but BOOTSTRAP_REQUIRED=$BOOTSTRAP_REQUIRED; continuing"
fi

# Run database import if S3 credentials are provided
if [ -n "$S3_BUCKET" ] && [ -n "$S3_DATABASE_PATH" ]; then
  log "S3 database import configured, running import-database..."
  if /usr/local/bin/import-database; then
    log "Database import completed successfully"
  else
    log "Database import failed or skipped"
  fi
else
  log "S3 database import not configured (S3_BUCKET and/or S3_DATABASE_PATH not set)"
fi

# Run proxy setup if origin URL is provided
if [ -n "$ORIGIN_URL" ]; then
  log "File proxy configured, running setup-proxy..."
  if /usr/local/bin/setup-proxy; then
    log "Proxy configuration completed successfully"
  else
    log "Proxy configuration failed or skipped"
  fi
else
  log "File proxy not configured (ORIGIN_URL not set)"
fi

log "Deployment initialization complete, executing: $*"

# Execute the provided command (from CMD or docker run override)
exec "$@"
