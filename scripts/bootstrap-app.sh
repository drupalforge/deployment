#!/bin/bash
# Bootstrap Application Script
# Prepares the application code for deployment:
# 1. Initialize and update Git submodules (with recursion)
# 2. Run composer install if composer.json exists

set -e

LOG_FILE="/tmp/drupalforge-deployment.log"

# Function to log messages
log() {
  local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [BOOTSTRAP] $*"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"
}

# Function to log errors
error() {
  local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [BOOTSTRAP] ERROR: $*"
  echo "$msg" >&2
  echo "$msg" >> "$LOG_FILE"
  return 1
}

ensure_devpanel_settings_include() {
  local app_root="$1"
  local settings_file="${WEB_ROOT:-${app_root}/web}/sites/default/settings.php"

  if [ ! -f "$settings_file" ]; then
    log "Drupal settings.php not found at $settings_file, skipping DevPanel settings include"
    return 0
  fi

  if grep -qE "(getenv\([\"']DP_APP_ID[\"']\)|\\\$_ENV\[[\"']DP_APP_ID[\"']\])" "$settings_file"; then
    log "DevPanel settings include already exists in $settings_file"
    return 0
  fi

  cat >> "$settings_file" <<'PHP'

/**
 * Load DevPanel override configuration, if available.
 */
$devpanel_settings = '/usr/local/share/drupalforge/settings.devpanel.php';
if (getenv('DP_APP_ID') !== FALSE && file_exists($devpanel_settings)) {
  include $devpanel_settings;
}
PHP

  log "Added DevPanel settings include block to $settings_file"
}

# Main execution
main() {
  local app_root="${APP_ROOT:-.}"
  
  log "Starting application bootstrap"
  log "Running as user: $(id)"
  
  # Check if app root exists
  if [ ! -d "$app_root" ]; then
    error "APP_ROOT does not exist: $app_root"
    return 1
  fi
  
  cd "$app_root"
  log "Working in: $(pwd)"
  log "Directory owner: $(stat -c '%U (%u)' "$(pwd)" 2>/dev/null || echo 'unknown')"
  
  # Initialize and update Git submodules recursively
  if [ -d ".git" ]; then
    log "Initializing Git submodules..."
    # Add current directory as safe directory to avoid dubious ownership errors
    git config --global --add safe.directory "$(pwd)" || true
    if git submodule update --init --recursive; then
      log "Git submodules initialized successfully"
    else
      error "Failed to initialize Git submodules"
      return 1
    fi
  else
    log "Not a Git repository (no .git directory), skipping submodule initialization"
  fi
  
  # Run composer install if composer.json exists
  if [ -f "composer.json" ]; then
    log "Found composer.json, running composer install..."
    
    # Check if composer is available
    if ! command -v composer &> /dev/null; then
      error "Composer is not available in PATH"
      return 1
    fi
    
    log "Composer version: $(composer --version 2>&1 || echo 'unknown')"
    log "PHP version: $(php --version 2>&1 | head -1 || echo 'unknown')"
    log "composer.lock present: $([ -f composer.lock ] && echo 'yes' || echo 'no')"
    log "vendor/autoload.php present: $([ -f vendor/autoload.php ] && echo 'yes' || echo 'no')"

    local composer_log
    composer_log=$(mktemp)
    trap 'rm -f "$composer_log"' EXIT

    log "Running composer install..."
    set +e  # Temporarily disable exit on error
    composer install --no-interaction 2>&1 | tee "$composer_log"
    local composer_exit=${PIPESTATUS[0]}
    set -e  # Re-enable exit on error

    if [ "$composer_exit" -eq 0 ]; then
      log "Composer dependencies installed successfully"
    # Handle lock file write issues for mounted volumes only when install artifacts exist.
    elif grep -qi "composer.lock.*permission" "$composer_log" && [ -f "vendor/autoload.php" ]; then
      log "Composer install completed but could not write lock file (permission denied)"
      log "Dependencies are present; continuing startup"
    else
      error "Failed to install composer dependencies (exit code: $composer_exit)"
      return 1
    fi
  else
    log "No composer.json found, skipping composer install"
  fi

  ensure_devpanel_settings_include "$app_root"
  
  log "Application bootstrap completed successfully"
  return 0
}

# Run main function
main "$@"
