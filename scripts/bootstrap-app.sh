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
    
    # Run composer install (allow lock file write failures for mounted volumes)
    # Note: When using mounted volumes with different ownership (e.g., in integration tests),
    # composer may fail to write composer.lock. This is expected and we handle it gracefully.
    set +e  # Temporarily disable exit on error
    composer_output=$(composer install --no-interaction 2>&1)
    composer_exit=$?
    set -e  # Re-enable exit on error
    
    if [ $composer_exit -eq 0 ]; then
      log "Composer dependencies installed successfully"
    else
      # Check if the failure was just because of lock file permissions
      if echo "$composer_output" | grep -iq "composer.lock.*permission"; then
        log "Composer install completed but could not write lock file (permission denied)"
        log "This is expected when using mounted volumes with different owners"
      else
        error "Failed to install composer dependencies"
        echo "$composer_output" >&2
        return 1
      fi
    fi
  else
    log "No composer.json found, skipping composer install"
  fi
  
  log "Application bootstrap completed successfully"
  return 0
}

# Run main function
main "$@"
