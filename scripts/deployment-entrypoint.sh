#!/bin/bash
# Deployment Entrypoint
# This script runs deployment setup tasks before executing the main command:
# 1. Fix ownership of FILE_PROXY_PATHS for the proxy handler (if ORIGIN_URL is configured)
# 2. Bootstrap application (Git submodules, composer install)
# 3. Import database from S3 (if configured)
# 4. Configure file proxy (if configured)
# 5. Execute the provided command (defaults to Apache startup)

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

# Create and fix ownership of FILE_PROXY_PATHS for the proxy handler (if ORIGIN_URL is configured)
if [ -n "$ORIGIN_URL" ] && [ -n "$FILE_PROXY_PATHS" ]; then
  current_uid=$(id -u)
  current_gid=$(id -g)
  IFS=',' read -ra _proxy_paths <<< "$FILE_PROXY_PATHS"
  for _path in "${_proxy_paths[@]}"; do
    _path=$(echo "$_path" | xargs)
    [[ "$_path" != /* ]] && _path="/$_path"
    full_path="${WEB_ROOT}${_path}"
    if [ ! -d "$full_path" ]; then
      if ! mkdir -p "$full_path" 2>/dev/null; then
        sudo install -d -o "$current_uid" -g "$current_gid" -m 0755 "$full_path"
      fi
      log "Created proxy path directory: $full_path"
    else
      if sudo -n chown --version &>/dev/null; then
        owner_uid=$(stat -c '%u' "$full_path" 2>/dev/null || echo "$current_uid")
        if [ "$owner_uid" != "$current_uid" ]; then
          sudo chown -R "$current_uid:$current_gid" "$full_path" 2>/dev/null || true
          log "Ownership fixed for proxy path: $full_path"
        fi
      fi
    fi
  done
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
