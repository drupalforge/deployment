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
      if (cd "$drupal_root" && composer show drupal/stage_file_proxy < /dev/null &> /dev/null); then
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

  if [ ! -f "/etc/apache2/sites-available/000-default.conf" ] && \
     [ ! -f "/templates/000-default.conf" ]; then
    error "Apache vhost configuration file does not exist at /etc/apache2/sites-available/000-default.conf or /templates/000-default.conf"
    return 1
  fi

  # Normalize proxied paths and inject per-path rewrite rules into vhost config.
  local normalized_paths=()

  for path in "${proxy_paths[@]}"; do
    path=$(echo "$path" | xargs)
    [ -z "$path" ] && continue
    [[ "$path" != /* ]] && path="/$path"
    normalized_paths+=("$path")
  done

  if [ ${#normalized_paths[@]} -eq 0 ]; then
    normalized_paths+=("/sites/default/files")
  fi

  # Inject managed rewrite rules into the active vhost scope.
  local vhost_block
  local vhost_output
  vhost_block=$(mktemp)
  vhost_output=$(mktemp)

  {
    printf '    # BEGIN DRUPALFORGE PROXY RULES (managed by setup-proxy.sh)\n'
    # Make ORIGIN_URL and WEB_ROOT available to the PHP handler at request time.
    # PHP running under Apache does not inherit shell environment variables; these
    # SetEnv directives are the standard Apache mechanism to pass values to PHP.
    printf '    SetEnv ORIGIN_URL "%s"\n' "$origin_url"
    printf '    SetEnv WEB_ROOT "%s"\n' "$web_root"
    printf '\n'
    printf '    <IfModule mod_rewrite.c>\n'
    printf '        RewriteEngine On\n'
    printf '\n'
    # In VirtualHost context %{REQUEST_FILENAME} equals REQUEST_URI (not a
    # filesystem path), so use %{DOCUMENT_ROOT}%{REQUEST_URI} for -f/-d checks.
    printf '        # Existing files/dirs should be served directly by Apache.\n'
    printf '        RewriteCond %%{DOCUMENT_ROOT}%%{REQUEST_URI} -f [OR]\n'
    printf '        RewriteCond %%{DOCUMENT_ROOT}%%{REQUEST_URI} -d\n'
    printf '        RewriteRule ^ - [L]\n'
    printf '\n'

    for path in "${normalized_paths[@]}"; do
      # Rule 1: image style proxy — fires only when the original source file is missing.
      # Condition 1 is a POSITIVE (non-negated) match so that the capture group
      # sets %1 to the original file's subpath (the portion after /public/).
      # Condition 2 then uses %1 to test that the original file is absent on disk.
      printf '        # Image style proxy: %s\n' "$path"
      printf '        RewriteCond %%{REQUEST_URI} ^%s/styles/[^/]+/public/(.+)$\n' "$path"
      printf '        RewriteCond %%{DOCUMENT_ROOT}%s/%%1 !-f\n' "$path"
      printf '        RewriteRule ^ /drupalforge-proxy-handler.php [END,PT]\n'
      printf '\n'
      # Rule 2: regular file proxy — handles non-image-style files under the proxy path.
      # Excludes styles/ subtree so that when the original exists and Drupal needs to
      # generate a derivative, the request falls through to Drupal's own routing.
      printf '        # File proxy: %s\n' "$path"
      printf '        RewriteCond %%{REQUEST_URI} !^%s/styles/\n' "$path"
      printf '        RewriteCond %%{REQUEST_URI} ^%s(/|$)\n' "$path"
      printf '        RewriteRule ^ /drupalforge-proxy-handler.php [END,PT]\n'
      printf '\n'
    done
    printf '    </IfModule>\n'
    printf '    # END DRUPALFORGE PROXY RULES (managed by setup-proxy.sh)\n'
  } > "$vhost_block"

  local vhost_applied=0
  local vhost_target
  local -a vhost_targets=()

  # Write to both template and sites-available so rules persist across restarts.
  # The loop below skips files that don't exist, so it's safe to list both.
  vhost_targets+=("/templates/000-default.conf")
  vhost_targets+=("/etc/apache2/sites-available/000-default.conf")

  for vhost_target in "${vhost_targets[@]}"; do
    [ -f "$vhost_target" ] || continue

    if awk -v block_file="$vhost_block" '
    BEGIN {
      inserted=0
      skip=0
      start_marker="^[[:space:]]*# BEGIN DRUPALFORGE PROXY RULES \\(managed by setup-proxy\\.sh\\)"
      end_marker="^[[:space:]]*# END DRUPALFORGE PROXY RULES \\(managed by setup-proxy\\.sh\\)"
    }

    skip {
      if ($0 ~ end_marker) {
        skip=0
      }
      next
    }

    $0 ~ start_marker {
      skip=1
      next
    }

    # Inject proxy rules immediately after the opening <VirtualHost ...> tag so
    # they are evaluated FIRST — before any catch-all PHP routing rules that the
    # base image may already have in the VirtualHost block (e.g. RewriteRule ^
    # index.php [L]).  Injecting at the end (before </VirtualHost>) would allow
    # those catch-all rules to intercept image-style requests before our proxy
    # rules ever run.
    /^[[:space:]]*<VirtualHost[[:space:]>]/ {
      print
      if (inserted==0) {
        while ((getline block_line < block_file) > 0) {
          print block_line
        }
        close(block_file)
        inserted=1
      }
      next
    }

    { print }

    END {
      if (inserted==0) {
        exit 1
      }
    }
  ' "$vhost_target" > "$vhost_output"; then
      # shellcheck disable=SC2024  # < redirect reads temp file; tee writes vhost file with sudo
      if sudo -n tee "$vhost_target" < "$vhost_output" >/dev/null 2>&1 || \
         tee "$vhost_target" < "$vhost_output" >/dev/null 2>&1; then
        log "Rewrite rules added to Apache vhost configuration: $vhost_target"
        vhost_applied=1
      else
        log "Warning: Failed to write rewrite rules to Apache vhost configuration: $vhost_target"
      fi
    else
      log "Warning: Failed to configure proxy rules in Apache vhost configuration: $vhost_target"
    fi
  done

  if [ "$vhost_applied" -eq 0 ]; then
    rm -f "$vhost_block" "$vhost_output"
    error "Failed to configure proxy rules in Apache vhost configuration"
    return 1
  fi

  rm -f "$vhost_block" "$vhost_output"

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
    # and conflicts with the normal startup sequence. Use pgrep to check for the
    # apache2 process without any side effects (no connection to port 80 needed).
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
