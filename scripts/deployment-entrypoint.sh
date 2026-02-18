#!/bin/bash
# Deployment Entrypoint
# This script runs deployment setup tasks before executing the main command:
# 1. Bootstrap application (Git submodules, composer install)
# 2. Import database from S3 (if configured)
# 3. Configure file proxy (if configured)
# 4. Execute the provided command (defaults to Apache startup)

set -e

# Function to log messages
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [DEPLOYMENT] $*"
}

log "Starting Drupal Forge deployment initialization"

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
# If no command provided, default to the base image's CMD (from BASE_CMD env var)
# This allows: docker run image → runs base image's CMD (from BASE_CMD)
#             docker run image /bin/bash → runs /bin/bash (override)
if [ $# -eq 0 ]; then
  # No command provided, use base image's default from BASE_CMD environment variable
  # BASE_CMD is set at build time from the base image's CMD
  if [ -n "${BASE_CMD}" ]; then
    log "Executing base image CMD: ${BASE_CMD}"
    exec ${BASE_CMD}
  else
    # Fallback if BASE_CMD not set (shouldn't happen)
    log "Warning: BASE_CMD not set, using hardcoded fallback"
    exec sudo -E /bin/bash /scripts/apache-start.sh
  fi
else
  # Command provided, execute it
  exec "$@"
fi
