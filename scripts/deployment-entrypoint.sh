#!/bin/bash
# Deployment Entrypoint
# This script runs deployment setup tasks before executing the main command:
# 1. Bootstrap application (Git submodules, composer install)
# 2. Create FILE_PROXY_PATHS directories with correct ownership (always required by Drupal)
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
# Root-owned entries (e.g. lost+found created by the mounted volume filesystem)
# are ignored when determining whether APP_ROOT has been populated.
_app_root_non_root_contents() {
  find "$APP_ROOT" -maxdepth 1 -mindepth 1 ! -user root 2>/dev/null
}
if [ "$APP_ROOT_TIMEOUT" -gt 0 ] && [ -d "$APP_ROOT" ]; then
  elapsed=0
  while [ -z "$(_app_root_non_root_contents)" ]; do
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
  if [ -n "$(_app_root_non_root_contents)" ]; then
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

# Create FILE_PROXY_PATHS directories and fix ownership for the proxy handler.
# Drupal requires these paths to exist with correct permissions regardless of
# whether file proxying is configured.
# Get APACHE_RUN_USER/GROUP: prefer environment variables, then fall back to
# the defaults in /etc/apache2/envvars (www-data on standard Debian/Ubuntu Apache).
if [ -z "${APACHE_RUN_USER:-}" ] && [ -f /etc/apache2/envvars ]; then
  APACHE_RUN_USER=$(. /etc/apache2/envvars 2>/dev/null && echo "${APACHE_RUN_USER:-www-data}" || echo "www-data")
fi
if [ -z "${APACHE_RUN_GROUP:-}" ] && [ -f /etc/apache2/envvars ]; then
  APACHE_RUN_GROUP=$(. /etc/apache2/envvars 2>/dev/null && echo "${APACHE_RUN_GROUP:-www-data}" || echo "www-data")
fi
FILE_PROXY_PATHS="${FILE_PROXY_PATHS:-/sites/default/files}"
_apache_user="${APACHE_RUN_USER:-www-data}"
_apache_group="${APACHE_RUN_GROUP:-www-data}"
IFS=',' read -ra _proxy_paths <<< "$FILE_PROXY_PATHS"
for _path in "${_proxy_paths[@]}"; do
  _path=$(echo "$_path" | xargs)
  [[ "$_path" != /* ]] && _path="/$_path"
  full_path="${WEB_ROOT}${_path}"
  if [ ! -d "$full_path" ]; then
    sudo -n install -d -o "$_apache_user" -g "$_apache_group" -m 0755 "$full_path"
    log "Created proxy path directory: $full_path"
  fi
  sudo -n chown -R "$_apache_user:$_apache_group" "$full_path"
  log "Ownership set for proxy path: $full_path (owner: $_apache_user)"
done

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
