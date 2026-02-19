#!/bin/bash
# Deployment Entrypoint
# This script runs deployment setup tasks before executing the main command:
# 1. Fix file ownership for mounted volumes (if running as root)
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

# Fix file ownership if running as root and APP_ROOT is mounted
if [ "$(id -u)" -eq 0 ]; then
  APP_ROOT="${APP_ROOT:-/var/www/html}"
  if [ -d "$APP_ROOT" ]; then
    log "Running as root, fixing ownership of $APP_ROOT..."
    # Get the target user from USER environment variable (from base image)
    TARGET_USER="${USER:-www}"
    chown -R "$TARGET_USER:$TARGET_USER" "$APP_ROOT" 2>/dev/null || true
    log "Ownership fixed, will switch to user $TARGET_USER after initialization"
  fi
fi

# Bootstrap application code
log "Bootstrapping application (submodules, composer)..."
if /usr/local/bin/bootstrap-app; then
  log "Application bootstrap completed"
else
  log "Application bootstrap failed or skipped"
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

log "Deployment initialization complete, executing main command..."

# Execute the provided command (from CMD or docker run override)
# If we're root and have a target user, switch to that user using sudo
if [ "$(id -u)" -eq 0 ] && [ -n "${USER:-}" ]; then
  log "Switching to user ${USER} and executing: $*"
  exec sudo -u "${USER}" -E "$@"
else
  exec "$@"
fi
