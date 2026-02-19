#!/bin/bash
set -e

# Setup Proxy Script
# This script configures file proxy for the Drupal site
# It supports two modes:
#   1. Stage File Proxy (if module is installed)
#   2. Apache reverse proxy (for on-demand file retrieval)
#
# Environment variables:
#   ORIGIN_URL - Origin site URL for file proxy (required)
#   FILE_PROXY_PATHS - Comma-separated paths relative to web root to proxy (for Apache proxy)
#                      Example: "/sites/default/files,/config"
#   USE_STAGE_FILE_PROXY - Set to "yes" to prefer Stage File Proxy if available (default: auto-detect)
#   WEB_ROOT - Web root path (default: /var/www/html/web)

# Function to log messages
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Function to log errors
error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
  return 1
}

# Check if Stage File Proxy module is installed
has_stage_file_proxy() {
  local drupal_root="${1:-.}"
  
  # Check if composer is available and composer.json exists
  if command -v composer &> /dev/null && [ -f "$drupal_root/composer.json" ] && [ -r "$drupal_root/composer.json" ]; then
    # Validate drupal_root exists and is accessible before using composer
    if [ -d "$drupal_root" ]; then
      # Use composer to check if stage_file_proxy package is installed
      if (cd "$drupal_root" && composer show drupal/stage_file_proxy &> /dev/null); then
        return 0
      fi
    fi
  fi
  
  return 1
}

# Enable and configure Stage File Proxy via Drush
configure_stage_file_proxy() {
  local origin_url="$1"
  
  log "Configuring Stage File Proxy with origin: $origin_url"
  
  # Enable the module
  if command -v drush &> /dev/null; then
    if drush pm:enable stage_file_proxy -y; then
      log "Stage File Proxy module enabled"
    else
      error "Failed to enable Stage File Proxy module"
      return 1
    fi
    
    # Configure origin URL
    if drush config:set stage_file_proxy.settings origin "$origin_url" -y; then
      log "Stage File Proxy configured with origin URL"
      return 0
    else
      error "Failed to configure Stage File Proxy"
      return 1
    fi
  else
    log "Drush not found in PATH, attempting manual configuration"
    # Drush not available - this is intentional for environments that use web UI
    return 0
  fi
}

# Configure Apache proxy with conditional file serving
# Serves local files if they exist, downloads and saves to real path if missing
configure_apache_proxy() {
  local origin_url="$1"
  local file_paths="$2"
  local web_root="${3:-/var/www/html/web}"
  local apache_conf="/etc/apache2/conf-available/drupalforge-proxy.conf"
  local handler_source="/var/www/drupalforge-proxy-handler.php"
  local handler_dest="${web_root}/../drupalforge-proxy-handler.php"
  
  log "Configuring Apache proxy with on-demand download"
  log "Files will be served locally if they exist, downloaded to real path if missing"
  log "Origin: $origin_url"
  
  # Copy proxy handler to web root parent (so it's accessible but not in public files)
  if [ -f "$handler_source" ]; then
    log "Setting up proxy handler at $handler_dest"
    cp "$handler_source" "$handler_dest"
    chmod 644 "$handler_dest"
    chown www-data:www-data "$handler_dest" 2>/dev/null || true
  else
    error "Proxy handler source not found at $handler_source"
    return 1
  fi
  
  # Build rewrite rules from comma-separated paths
  local rewrite_rules=""
  
  if [ -n "$file_paths" ]; then
    # Split comma-separated paths and create rewrite rules
    IFS=',' read -ra paths <<< "$file_paths"
    for path in "${paths[@]}"; do
      # Trim whitespace
      path=$(echo "$path" | xargs)
      # Ensure path starts with /
      [[ "$path" != /* ]] && path="/$path"
      
      # Create rewrite rule: if path matches AND file doesn't exist locally AND it's not a directory,
      # then rewrite to proxy handler
      rewrite_rules+="  # Proxy handler: $path\n"
      rewrite_rules+="  RewriteCond %{REQUEST_URI} ^${path}\n"
      rewrite_rules+="  RewriteCond %{REQUEST_FILENAME} !-f\n"
      rewrite_rules+="  RewriteCond %{REQUEST_FILENAME} !-d\n"
      rewrite_rules+="  RewriteRule ^${path}(/.*)?$ /drupalforge-proxy-handler.php [QSA,L]\n"
      rewrite_rules+="  \n"
    done
  else
    # Default to /sites/default/files if not specified
    log "No FILE_PROXY_PATHS specified, using default: /sites/default/files"
    rewrite_rules+="  # Proxy handler: /sites/default/files\n"
    rewrite_rules+="  RewriteCond %{REQUEST_URI} ^/sites/default/files\n"
    rewrite_rules+="  RewriteCond %{REQUEST_FILENAME} !-f\n"
    rewrite_rules+="  RewriteCond %{REQUEST_FILENAME} !-d\n"
    rewrite_rules+="  RewriteRule ^/sites/default/files(/.*)?$ /drupalforge-proxy-handler.php [QSA,L]\n"
  fi
  
  # Append rewrite rules to existing configuration
  if [ -f "$apache_conf" ]; then
    log "Appending rewrite rules to existing configuration at $apache_conf"
    
    # Find the end of the mod_rewrite section and insert before it
    if grep -q "RewriteEngine On" "$apache_conf"; then
      # Insert rules after RewriteBase (need sudo to write to /etc/apache2)
      if sudo -n sed -i "/RewriteBase \//a\\$(echo -e "$rewrite_rules")" "$apache_conf" 2>/dev/null; then
        log "Rewrite rules added to configuration"
      else
        log "Warning: Could not write to $apache_conf (permission denied)"
        return 1
      fi
    else
      log "Warning: RewriteEngine configuration not found, rewrite rules not added"
      return 1
    fi
  else
    log "Apache configuration file does not exist at $apache_conf"
    return 1
  fi
  
  # Enable mod_rewrite
  if sudo -n a2enmod rewrite 2>/dev/null; then
    log "mod_rewrite enabled"
  else
    log "mod_rewrite already enabled or failed to enable"
  fi
  
  # Test Apache configuration
  if sudo -n apache2ctl configtest 2>/dev/null | grep -q "Syntax OK"; then
    log "Apache configuration is valid"
    return 0
  else
    error "Apache configuration has errors"
    return 1
  fi
}

# Main execution
main() {
  local app_root="${APP_ROOT:-.}"
  local web_root="${WEB_ROOT:-/var/www/html/web}"
  local origin_url="${ORIGIN_URL}"
  local file_proxy_paths="${FILE_PROXY_PATHS}"
  local use_stage_file_proxy="${USE_STAGE_FILE_PROXY}"
  
  log "Starting proxy configuration"
  
  # Check if origin URL is provided
  if [ -z "$origin_url" ]; then
    log "ORIGIN_URL not set, skipping proxy configuration"
    return 0
  fi
  
  # Normalize origin URL (remove trailing slash)
  origin_url="${origin_url%/}"
  
  # Auto-detect Stage File Proxy if not explicitly set
  if [ -z "$use_stage_file_proxy" ]; then
    if has_stage_file_proxy "$app_root"; then
      use_stage_file_proxy="yes"
    else
      use_stage_file_proxy="no"
    fi
  fi
  
  # Configure appropriate proxy method
  if [ "$use_stage_file_proxy" = "yes" ]; then
    if has_stage_file_proxy "$app_root"; then
      log "Detected Stage File Proxy module, configuring..."
      if configure_stage_file_proxy "$origin_url"; then
        log "Stage File Proxy configuration completed"
        return 0
      else
        error "Stage File Proxy configuration failed"
        return 1
      fi
    else
      log "Stage File Proxy not found, falling back to Apache proxy"
    fi
  fi
  
  # Configure Apache proxy as fallback or primary method
  if configure_apache_proxy "$origin_url" "$file_proxy_paths" "$web_root"; then
    log "Apache proxy configuration completed"
    return 0
  else
    error "Proxy configuration failed"
    return 1
  fi
}

# Run main function
main "$@"
