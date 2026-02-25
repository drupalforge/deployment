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

# Unified rewrite helper for both .htaccess and Apache config targets.
# Responsibilities:
# 1) Remove stale drupalforge-proxy-handler rewrite blocks
# 2) Add file/dir bypass if not already present
# 3) Inject fresh per-path rewrite rules at the requested anchor
update_proxy_rewrite_rules() {
  local file="$1"
  local insert_anchor_regex="$2"
  shift 2

  if [ ! -f "$file" ]; then
    return 1
  fi

  local block_file
  local output_file
  local normalized_paths=()
  local path
  local has_bypass=0
  block_file=$(mktemp)
  output_file=$(mktemp)

  for path in "$@"; do
    path=$(echo "$path" | xargs)
    [ -z "$path" ] && continue
    [[ "$path" != /* ]] && path="/$path"
    normalized_paths+=("$path")
  done

  if [ ${#normalized_paths[@]} -eq 0 ]; then
    normalized_paths+=("/sites/default/files")
  fi

  if grep -qE "^[[:space:]]*RewriteCond[[:space:]]+%\{REQUEST_FILENAME\}[[:space:]]+-f([[:space:]]|$)|^[[:space:]]*RewriteCond[[:space:]]+%\{REQUEST_FILENAME\}[[:space:]]+-d([[:space:]]|$)" "$file"; then
    has_bypass=1
  fi

  : > "$block_file"
  for path in "${normalized_paths[@]}"; do
    printf '  # Proxy handler: %s\n' "$path" >> "$block_file"
    printf '  RewriteCond %%{REQUEST_URI} ^%s(/|$)\n' "$path" >> "$block_file"
    printf '  RewriteRule ^(.*)$ /drupalforge-proxy-handler.php [END]\n' >> "$block_file"
    printf '\n' >> "$block_file"
  done

  if awk -v block_file="$block_file" -v anchor="$insert_anchor_regex" -v has_bypass="$has_bypass" '
    BEGIN {
      inserted=0
      skip_proxy_block=0
    }

    /^[[:space:]]*# Proxy handler:/ {
      skip_proxy_block=1
      next
    }

    skip_proxy_block && /^[[:space:]]*RewriteCond.*REQUEST_URI/ {
      next
    }

    skip_proxy_block && /^[[:space:]]*RewriteRule.*drupalforge-proxy-handler/ {
      skip_proxy_block=0
      next
    }

    !skip_proxy_block && /^[[:space:]]*RewriteRule.*drupalforge-proxy-handler/ {
      next
    }

    !skip_proxy_block && inserted==0 && $0 ~ anchor {
      print

      if (has_bypass == 0) {
        print "  # Skip proxy for existing local files and directories."
        print "  RewriteCond %{REQUEST_FILENAME} -f [OR]"
        print "  RewriteCond %{REQUEST_FILENAME} -d"
        print "  RewriteRule ^ - [END]"
        print ""
      }

      while ((getline rule_line < block_file) > 0) {
        print rule_line
      }
      close(block_file)
      print ""

      inserted=1
      next
    }

    !skip_proxy_block {
      print
    }

    END {
      if (inserted == 0) {
        exit 1
      }
    }
  ' "$file" > "$output_file"; then
    if sudo -n tee "$file" < "$output_file" >/dev/null 2>&1 || \
       tee "$file" < "$output_file" >/dev/null 2>&1; then
      rm -f "$block_file" "$output_file"
      return 0
    fi
  fi

  rm -f "$block_file" "$output_file"
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
  local htaccess_file
  local proxy_paths=()

  log "Configuring Apache proxy with on-demand download"
  log "Files will be served locally if they exist, downloaded to real path if missing"
  log "Origin: $origin_url"

  # Normalize web root (strip trailing slash unless root itself)
  if [ "$web_root" != "/" ]; then
    web_root="${web_root%/}"
  fi

  htaccess_file="$web_root/.htaccess"

  # Ensure proxy handler exists at static path used by Apache Alias.
  if [ -f "$handler_source" ]; then
    chmod 644 "$handler_source"
    chown www-data:www-data "$handler_source" 2>/dev/null || true
    log "Proxy handler is available at $handler_source"
  else
    error "Proxy handler source not found at $handler_source"
    return 1
  fi

  # Parse proxied paths from comma-separated input; helper handles normalization.
  if [ -n "$file_paths" ]; then
    IFS=',' read -ra paths <<< "$file_paths"
    for path in "${paths[@]}"; do
      proxy_paths+=("$path")
    done
  else
    log "No FILE_PROXY_PATHS specified, using default: /sites/default/files"
    proxy_paths+=("/sites/default/files")
  fi

  # Configure rewrite rules in .htaccess first (closest to Drupal routing).
  local htaccess_success=false
  if [ -f "$htaccess_file" ]; then
    if update_proxy_rewrite_rules "$htaccess_file" '^[[:space:]]*RewriteEngine[[:space:]]+[Oo]n[[:space:]]*$' "${proxy_paths[@]}"; then
      log "Rewrite rules added to .htaccess"
      htaccess_success=true
    else
      log "Warning: Could not update rewrite rules in .htaccess"
    fi
  else
    log "No .htaccess found at $htaccess_file, using Apache config only"
  fi

  local apache_config_success=false
  if ! $htaccess_success && [ -f "$apache_conf" ]; then
    log "Using Apache global configuration for proxy rewrite rules"

    # Use WEB_ROOT for rewrite scope so per-directory RewriteRule backreferences
    # map to request paths under the site web root (without an extra web/ prefix).
    local directory_scope="$web_root"
    log "Using WEB_ROOT for rewrite scope: $directory_scope"

    local temp_scope
    temp_scope=$(mktemp)
    if awk -v dir="$directory_scope" '
      BEGIN { updated=0 }
      /^<Directory / && updated==0 {
        print "<Directory \"" dir "\">"
        updated=1
        next
      }
      { print }
      END { if (updated==0) exit 1 }
    ' "$apache_conf" > "$temp_scope" 2>/dev/null && \
       sudo -n tee "$apache_conf" < "$temp_scope" >/dev/null 2>&1; then
      log "Apache Directory scope set for rewrite rules: $directory_scope"
    else
      rm -f "$temp_scope"
      log "Warning: Could not update Apache Directory scope in $apache_conf"
      return 1
    fi
    rm -f "$temp_scope"

    if update_proxy_rewrite_rules "$apache_conf" '^[[:space:]]*RewriteEngine[[:space:]]+[Oo]n[[:space:]]*$' "${proxy_paths[@]}"; then
      log "Rewrite rules added to Apache configuration"
      apache_config_success=true
    else
      log "Warning: Could not update Apache rewrite rules in $apache_conf"
      return 1
    fi
  elif ! $htaccess_success; then
    log "Apache configuration file does not exist at $apache_conf"
  fi

  # Ensure at least .htaccess or Apache config was successfully configured
  if ! $htaccess_success && ! $apache_config_success; then
    error "Failed to configure proxy rules in either .htaccess or Apache configuration"
    return 1
  fi

  # Enable mod_rewrite
  if sudo -n a2enmod rewrite 2>/dev/null; then
    log "mod_rewrite enabled"
  else
    log "mod_rewrite already enabled or failed to enable"
  fi

  # Test Apache configuration
  if sudo -n apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
    log "Apache configuration is valid"

    # Reload only if Apache is already running.
    # In container startup flow, Apache starts after this script via CMD.
    if pgrep -x apache2 >/dev/null 2>&1; then
      if sudo -n apache2ctl graceful 2>/dev/null; then
        log "Apache reloaded successfully"
      else
        log "Warning: Could not reload Apache (may require manual reload)"
      fi
    else
      log "Apache not running yet; reload skipped"
    fi

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
