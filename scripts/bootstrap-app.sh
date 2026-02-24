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

ensure_settings_php_exists() {
  local app_root="$1"
  local has_default_settings="$2"
  local default_settings="${WEB_ROOT:-${app_root}/web}/sites/default/default.settings.php"
  local settings_file="${WEB_ROOT:-${app_root}/web}/sites/default/settings.php"
  local target_owner_spec current_spec

  if [ -f "$settings_file" ]; then
    log "Drupal settings.php already exists at $settings_file"
    return 0
  fi

  # Only create settings.php if default.settings.php did NOT exist BEFORE bootstrap
  # This means it was likely added during bootstrap (via git submodules or composer)
  if [ "$has_default_settings" -eq 1 ]; then
    log "default.settings.php existed before bootstrap; not auto-creating settings.php"
    return 0
  fi

  if [ ! -f "$default_settings" ]; then
    log "default.settings.php not found after bootstrap; cannot create settings.php"
    return 0
  fi

  log "Creating settings.php from default.settings.php that was added during bootstrap..."

  target_owner_spec="$(id -u):$(id -g)"
  if sudo -n cp "$default_settings" "$settings_file"; then
    # Cross-platform owner lookup: GNU/Linux uses `stat -c`, macOS/BSD uses `stat -f`.
    current_spec="$(stat -c '%u:%g' "$settings_file" 2>/dev/null || stat -f '%u:%g' "$settings_file" 2>/dev/null || true)"
    if [ -z "$target_owner_spec" ] || [ -z "$current_spec" ] || [ "$target_owner_spec" = "$current_spec" ] || sudo -n chown "$target_owner_spec" "$settings_file"; then
      log "Created settings.php from default.settings.php"
      return 0
    fi
  fi

  error "Failed to create settings.php from default.settings.php"
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

  local devpanel_block=$'
/**
 * Load DevPanel override configuration, if available.
 */
$devpanel_settings = \'/usr/local/share/drupalforge/settings.devpanel.php\';
if (getenv(\'DP_APP_ID\') !== FALSE && file_exists($devpanel_settings)) {
  include $devpanel_settings;
}'

  if echo "$devpanel_block" | sudo -n tee -a "$settings_file" >/dev/null; then
    log "Added DevPanel settings include block to $settings_file"
  else
    error "Failed to add DevPanel settings include block to $settings_file"
    return 1
  fi
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
  # Cross-platform directory owner lookup: GNU/Linux `stat -c` and macOS/BSD `stat -f`.
  log "Directory owner: $(stat -c '%U (%u)' "$(pwd)" 2>/dev/null || stat -f '%Su (%u)' "$(pwd)" 2>/dev/null || echo 'unknown')"
  
  # Check if default.settings.php exists BEFORE bootstrap
  # We'll use this to determine if we should create settings.php
  local default_settings="${WEB_ROOT:-${app_root}/web}/sites/default/default.settings.php"
  local has_default_settings=0
  if [ -f "$default_settings" ]; then
    has_default_settings=1
    log "default.settings.php exists before bootstrap; will NOT auto-create settings.php"
  else
    log "default.settings.php does not exist before bootstrap; will create settings.php if it appears during bootstrap"
  fi
  
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

  ensure_settings_php_exists "$app_root" "$has_default_settings"
  ensure_devpanel_settings_include "$app_root"
  
  log "Application bootstrap completed successfully"
  return 0
}

# Run main function
main "$@"
