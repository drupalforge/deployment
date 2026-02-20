#!/bin/bash
# Bootstrap Application Script
# Prepares the application code for deployment:
# 1. Initialize and update Git submodules (with recursion)
# 2. Run composer install if composer.json exists

set -e

# Function to log messages
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [BOOTSTRAP] $*"
}

# Function to log errors
error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [BOOTSTRAP] ERROR: $*" >&2
  return 1
}

# Main execution
main() {
  local app_root="${APP_ROOT:-.}"
  local composer_install_retries="${COMPOSER_INSTALL_RETRIES:-3}"
  local composer_retry_delay="${COMPOSER_RETRY_DELAY:-5}"
  
  log "Starting application bootstrap"
  
  # Check if app root exists
  if [ ! -d "$app_root" ]; then
    error "APP_ROOT does not exist: $app_root"
    return 1
  fi
  
  cd "$app_root"
  log "Working in: $(pwd)"
  
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
    
    # Validate retry settings
    if ! [[ "$composer_install_retries" =~ ^[0-9]+$ ]] || [ "$composer_install_retries" -lt 1 ]; then
      error "COMPOSER_INSTALL_RETRIES must be a positive integer (got: $composer_install_retries)"
      return 1
    fi

    if ! [[ "$composer_retry_delay" =~ ^[0-9]+$ ]]; then
      error "COMPOSER_RETRY_DELAY must be a non-negative integer (got: $composer_retry_delay)"
      return 1
    fi

    local attempt=1
    local composer_output=""
    local composer_exit=1

    while [ "$attempt" -le "$composer_install_retries" ]; do
      log "Running composer install (attempt $attempt/$composer_install_retries)..."

      set +e  # Temporarily disable exit on error
      composer_output=$(composer install --no-interaction 2>&1)
      composer_exit=$?
      set -e  # Re-enable exit on error

      if [ "$composer_exit" -eq 0 ]; then
        log "Composer dependencies installed successfully"
        break
      fi

      # Handle lock file write issues for mounted volumes only when install artifacts exist.
      if echo "$composer_output" | grep -iq "composer.lock.*permission" && [ -f "vendor/autoload.php" ]; then
        log "Composer install completed but could not write lock file (permission denied)"
        log "Dependencies are present; continuing startup"
        break
      fi

      if [ "$attempt" -lt "$composer_install_retries" ]; then
        log "Composer install failed on attempt $attempt. Retrying in ${composer_retry_delay}s..."
        if [ "$composer_retry_delay" -gt 0 ]; then
          sleep "$composer_retry_delay"
        fi
      else
        error "Failed to install composer dependencies after $composer_install_retries attempt(s)"
        echo "$composer_output" >&2
        return 1
      fi

      attempt=$((attempt + 1))
    done
  else
    log "No composer.json found, skipping composer install"
  fi
  
  log "Application bootstrap completed successfully"
  return 0
}

# Run main function
main "$@"
