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
  local proxy_paths=()

  log "Configuring Apache proxy with on-demand download"
  log "Files will be served locally if they exist, downloaded to real path if missing"
  log "Origin: $origin_url"

  # Normalize web root (strip trailing slash unless root itself)
  if [ "$web_root" != "/" ]; then
    web_root="${web_root%/}"
  fi

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

  if [ ! -f "$apache_conf" ]; then
    error "Apache configuration file does not exist at $apache_conf"
    return 1
  fi

  # Update the Directory scope to the current web root.
  local temp_scope
  temp_scope=$(mktemp)
  # shellcheck disable=SC2024  # < redirect reads temp_scope (no elevated read needed); tee writes conf with sudo
  if awk -v dir="$web_root" '
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
    log "Apache Directory scope set for rewrite rules: $web_root"
  else
    rm -f "$temp_scope"
    log "Warning: Could not update Apache Directory scope in $apache_conf"
    return 1
  fi
  rm -f "$temp_scope"

  # Normalize proxied paths and inject per-path rewrite rules into the Apache config.
  local normalized_paths=()
  local block_file output_file
  block_file=$(mktemp)
  output_file=$(mktemp)

  for path in "${proxy_paths[@]}"; do
    path=$(echo "$path" | xargs)
    [ -z "$path" ] && continue
    [[ "$path" != /* ]] && path="/$path"
    normalized_paths+=("$path")
  done

  if [ ${#normalized_paths[@]} -eq 0 ]; then
    normalized_paths+=("/sites/default/files")
  fi

  # Build per-path proxy rules block.
  {
    for path in "${normalized_paths[@]}"; do
      # Image style bypass: if original exists, stop proxy and let Drupal generate the derivative.
      # Pattern: {path}/styles/{style}/public/{file} → check {path}/{file} exists.
      printf '    # Image style bypass: %s\n' "$path"
      printf '    RewriteCond %%{REQUEST_URI} ^%s/styles/[^/]+/public/(.+)$\n' "$path"
      printf '    RewriteCond %%{DOCUMENT_ROOT}%s/%%1 -f\n' "$path"
      printf '    RewriteRule ^ - [L]\n'
      printf '\n'
      printf '    # Proxy handler: %s\n' "$path"
      printf '    RewriteCond %%{REQUEST_URI} ^%s(/|$)\n' "$path"
      printf '    RewriteRule ^(.*)$ /drupalforge-proxy-handler.php [END]\n'
      printf '\n'
    done
  } > "$block_file"

  if awk -v block_file="$block_file" '
    # The anchor is the label comment hard-coded in apache-proxy.conf (config template);
    # it marks where per-path rules should be injected.
    BEGIN {
      anchor="^[[:space:]]*# Per-path proxy rules configured by setup-proxy\\.sh"
      inserted=0
      skip_proxy_block=0
    }

    # Strip stale per-path proxy blocks (image style bypass and proxy handler).
    /^[[:space:]]*# (Image style bypass|Proxy handler):/ {
      skip_proxy_block=1
      next
    }

    skip_proxy_block {
      if (/^[[:space:]]*RewriteRule.*drupalforge-proxy-handler/ || \
          /^[[:space:]]*RewriteRule \^ - \[L\]/) {
        skip_proxy_block=0
      }
      next
    }

    !skip_proxy_block && /^[[:space:]]*RewriteRule.*drupalforge-proxy-handler/ {
      next
    }

    # Inject fresh per-path rules after the anchor.
    !inserted && $0 ~ anchor {
      print
      while ((getline rule_line < block_file) > 0) {
        print rule_line
      }
      close(block_file)
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
  ' "$apache_conf" > "$output_file"; then
    # shellcheck disable=SC2024  # < redirect reads output_file (no elevated read needed); tee writes conf with sudo
    if sudo -n tee "$apache_conf" < "$output_file" >/dev/null 2>&1 || \
       tee "$apache_conf" < "$output_file" >/dev/null 2>&1; then
      rm -f "$block_file" "$output_file"
      log "Rewrite rules added to Apache configuration"
    else
      rm -f "$block_file" "$output_file"
      error "Failed to write rewrite rules to Apache configuration"
      return 1
    fi
  else
    rm -f "$block_file" "$output_file"
    error "Failed to configure proxy rules in Apache configuration"
    return 1
  fi

  # Enable the drupalforge-proxy conf (a2enconf is idempotent so always safe to call).
  # setup-proxy.sh owns the full conf lifecycle so that re-runs reliably reload the config.
  if sudo -n a2enconf drupalforge-proxy 2>/dev/null; then
    log "Apache conf drupalforge-proxy enabled"
  else
    log "Warning: Failed to enable Apache conf drupalforge-proxy"
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

    # Reload Apache only if it is already running so changes take effect immediately.
    # On normal container startup Apache has not started yet (CMD fires after this
    # script), so the updated config is picked up automatically when Apache starts.
    # Calling 'apache2ctl graceful' when Apache is not running starts it prematurely
    # and conflicts with the normal startup sequence.
    if pgrep -x apache2 >/dev/null 2>&1; then
      if sudo -n apache2ctl graceful 2>/dev/null; then
        log "Apache configuration reloaded"
      else
        log "Warning: Apache reload failed; config may need manual restart"
      fi
    else
      log "Apache not running yet; config will be applied on startup"
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
  # shellcheck disable=SC2153  # ORIGIN_URL, FILE_PROXY_PATHS, USE_STAGE_FILE_PROXY are runtime env vars
  local origin_url="${ORIGIN_URL}" file_proxy_paths="${FILE_PROXY_PATHS}" use_stage_file_proxy="${USE_STAGE_FILE_PROXY}"

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
