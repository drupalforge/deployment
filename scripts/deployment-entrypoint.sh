#!/bin/bash
# Deployment Entrypoint
# This script runs deployment setup tasks before executing the main command:
# 1. Bootstrap application (Git submodules, composer install)
# 2. Import database from S3 (if configured)
# 3. Configure file proxy (if configured)
# 4. Execute the provided command (defaults to Apache startup)

set -e

LOG_FILE="/tmp/drupalforge-deployment.log"

# Function to log messages
log() {
  local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [DEPLOYMENT] $*"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"
}

log "Starting Drupal Forge deployment initialization"
log "Entrypoint: $0"

BOOTSTRAP_REQUIRED="${BOOTSTRAP_REQUIRED:-yes}"
APP_ROOT_TIMEOUT="${APP_ROOT_TIMEOUT:-300}"
if ! [[ "$APP_ROOT_TIMEOUT" =~ ^[0-9]+$ ]]; then
  log "Warning: APP_ROOT_TIMEOUT must be a non-negative integer (got: $APP_ROOT_TIMEOUT); using default 300"
  APP_ROOT_TIMEOUT=300
fi

APP_ROOT="${APP_ROOT:-/var/www/html}"
WEB_ROOT="${WEB_ROOT:-$APP_ROOT/web}"

# Wait for APP_ROOT to be non-empty before proceeding.
# DevPanel clones the repository into APP_ROOT after the container starts,
# so the directory may be empty on first boot until the clone completes.
if [ "$APP_ROOT_TIMEOUT" -gt 0 ] && [ -d "$APP_ROOT" ]; then
  elapsed=0
  while [ -z "$(ls -A "$APP_ROOT" 2>/dev/null)" ]; do
    if [ "$elapsed" -eq 0 ]; then
      log "Waiting for APP_ROOT to be populated: $APP_ROOT (timeout: ${APP_ROOT_TIMEOUT}s)"
    fi
    if [ "$elapsed" -ge "$APP_ROOT_TIMEOUT" ]; then
      log "Warning: APP_ROOT is still empty after ${APP_ROOT_TIMEOUT}s; continuing anyway"
      break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  if [ -n "$(ls -A "$APP_ROOT" 2>/dev/null)" ]; then
    log "APP_ROOT is ready: $APP_ROOT"
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
