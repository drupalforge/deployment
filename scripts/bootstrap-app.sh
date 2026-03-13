#!/bin/bash
# Bootstrap Application Script
# Prepares the application code for deployment:
# 1. Initialize and update Git submodules (with recursion)
# 2. Run composer install if composer.json exists

set -e

LOG_FILE="/tmp/drupalforge-deployment.log"

# Function to log messages
log() {
  local msg
  msg="[$(date +'%Y-%m-%d %H:%M:%S')] [BOOTSTRAP] $*"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"
}

# Function to log errors
error() {
  local msg
  msg="[$(date +'%Y-%m-%d %H:%M:%S')] [BOOTSTRAP] ERROR: $*"
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

  if grep -q "settings.devpanel.php" "$settings_file"; then
    log "DevPanel settings include already exists in $settings_file"
    return 0
  fi

  local devpanel_block=$'
/**
 * Load DevPanel override configuration, if available.
 */
$devpanel_settings = dirname($app_root, 2) . \'/settings.devpanel.php\';
if (file_exists($devpanel_settings)) {
  include $devpanel_settings;
}'

  if echo "$devpanel_block" | sudo -n tee -a "$settings_file" >/dev/null; then
    log "Added DevPanel settings include block to $settings_file"
  else
    error "Failed to add DevPanel settings include block to $settings_file"
    return 1
  fi
}

resolve_drupal_settings_paths() {
  local app_root="${WEB_ROOT:-$1/web}"
  local settings_file="${app_root}/sites/default/settings.php"

  if [ ! -f "$settings_file" ]; then
    return 2
  fi

  php -d display_errors=0 -d error_reporting=0 \
    -- --app_root="$app_root" --settings_file="$settings_file" \
    <<'PHPCODE' 2>/dev/null
<?php
$options = getopt("", ["app_root:", "settings_file:"]);
extract($options, EXTR_SKIP);

$settings = [];
$databases = [];
define("DRUPAL_ROOT", $app_root);
ob_start();
include $settings_file;
ob_end_clean();
$config_sync = $settings["config_sync_directory"] ?? null;
if (!is_string($config_sync)) {
  $config_sync = "";
}
$config_sync = trim($config_sync);
if ($config_sync !== "" && !preg_match("/^(\/|[A-Za-z]:[\\\/])/", $config_sync)) {
  $config_sync = rtrim($app_root, "/\\") . "/" . $config_sync;
}
$private_path = $settings["file_private_path"] ?? "";
if (!is_string($private_path)) {
  $private_path = "";
}
$private_path = trim($private_path);
if ($private_path !== "" &&
    !str_starts_with($private_path, "/") &&
    !preg_match("/^[A-Za-z]:[\\\\\/]/", $private_path)) {
  $private_path = rtrim($app_root, "/\\") . "/" . $private_path;
}
echo $config_sync . PHP_EOL . $private_path;
PHPCODE
}

resolve_apache_owner_spec() {
  local apache_user="${APACHE_RUN_USER:-}"
  local apache_group="${APACHE_RUN_GROUP:-}"

  if [ -z "$apache_user" ] && [ -f /etc/apache2/envvars ]; then
    # shellcheck disable=SC1091
    apache_user=$(. /etc/apache2/envvars 2>/dev/null && echo "${APACHE_RUN_USER:-www-data}" || echo "www-data")
  fi
  if [ -z "$apache_group" ] && [ -f /etc/apache2/envvars ]; then
    # shellcheck disable=SC1091
    apache_group=$(. /etc/apache2/envvars 2>/dev/null && echo "${APACHE_RUN_GROUP:-www-data}" || echo "www-data")
  fi

  if [ -z "$apache_user" ]; then
    apache_user="$(id -u)"
  fi
  if [ -z "$apache_group" ]; then
    apache_group="$(id -g)"
  fi

  echo "$apache_user:$apache_group"
}

ensure_directory_owned_by_apache() {
  local directory_path="$1"
  local directory_label="$2"
  local owner_spec

  owner_spec="$(resolve_apache_owner_spec)"
  if [ -z "$owner_spec" ]; then
    error "Failed to resolve Apache owner/group for $directory_label"
    return 1
  fi

  if sudo -n chown -R "$owner_spec" "$directory_path"; then
    log "Ownership set for $directory_label: $directory_path (owner/group: $owner_spec)"
    return 0
  fi

  error "Failed to set ownership for $directory_label: $directory_path (owner/group: $owner_spec)"
  return 1
}

ensure_settings_directories_exist() {
  local app_root="$1"
  local web_root="${WEB_ROOT:-${app_root}/web}"
  local settings_file="${web_root}/sites/default/settings.php"
  local resolved_paths config_sync_directory file_private_path

  set +e
  resolved_paths="$(resolve_drupal_settings_paths "$app_root")"
  local resolve_status=$?
  set -e

  if [ "$resolve_status" -eq 2 ]; then
    log "Drupal settings.php not found at $settings_file, skipping config sync/private directory creation"
    return 0
  fi

  if [ "$resolve_status" -ne 0 ]; then
    error "Failed to resolve Drupal directories from $settings_file"
    return 1
  fi

  config_sync_directory="${resolved_paths%%$'\n'*}"
  if [ "$resolved_paths" = "$config_sync_directory" ]; then
    file_private_path=""
  else
    file_private_path="${resolved_paths#*$'\n'}"
  fi

  if [ -z "$config_sync_directory" ]; then
    error "Failed to resolve config sync directory from $settings_file"
    return 1
  fi

  if [ -d "$config_sync_directory" ]; then
    log "Config sync directory already exists at $config_sync_directory"
  elif sudo -n mkdir -p "$config_sync_directory"; then
    log "Created config sync directory at $config_sync_directory"
  else
    error "Failed to create config sync directory at $config_sync_directory"
    return 1
  fi

  if [ -z "$file_private_path" ]; then
    log "Drupal file_private_path is empty or not set in $settings_file; skipping directory creation"
    return 0
  fi

  if [ -d "$file_private_path" ]; then
    log "Private files directory already exists at $file_private_path"
  elif sudo -n mkdir -p "$file_private_path"; then
    log "Created private files directory at $file_private_path"
  else
    error "Failed to create private files directory at $file_private_path"
    return 1
  fi

  ensure_directory_owned_by_apache "$file_private_path" "private files directory"
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
    if [ -n "${COMPOSER_INSTALL_FLAGS:-}" ]; then
      read -r -a composer_flags <<< "$COMPOSER_INSTALL_FLAGS"
    else
      composer_flags=()
    fi
    composer install -n --no-progress "${composer_flags[@]}" 2>&1 | tee "$composer_log"
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
  ensure_settings_directories_exist "$app_root"
  
  log "Application bootstrap completed successfully"
  return 0
}

# Run main function
main "$@"
