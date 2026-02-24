#!/bin/bash
# Sudo credential management library for test suites
# Provides consistent sudo setup, credential refresh, and cleanup across all tests

# Source utils library for _timeout helper
# shellcheck source=./utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Helper function to display interactive countdown with sudo password prompt.
# Used when sudo credentials are needed but not cached.
# Usage: _countdown_sudo_prompt temp_dir
# Arguments:
#   temp_dir: temporary directory for countdown stop flag file
# Returns: 0 if user successfully authenticated, 1 otherwise
_countdown_sudo_prompt() {
    local temp_dir="$1"
    local COUNTDOWN_STOP_FILE="$temp_dir/countdown-stop"
    
    # Define colors locally
    local YELLOW='\033[1;33m'
    local NC='\033[0m'
    
    echo -e "${YELLOW}Some tests require sudo. Enter your password to run them,${NC}"
    echo -e "${YELLOW}or press Ctrl-C to skip (30 second timeout).${NC}"
    
    # Print one countdown line, then each tick uses ANSI save/restore cursor
    # (\033[s/\033[u) so "Password:" stays below the countdown and the cursor
    # returns to exactly where sudo left it (after "Password: ").
    # A stop-flag file prevents one extra tick from firing after the user
    # presses Enter (which shifts the cursor and would overwrite the password line).
    printf "  (30 sec remaining)\n" > /dev/tty 2>/dev/null || true
    ( for i in $(seq 30 -1 1); do
          sleep 1
          [ -f "$COUNTDOWN_STOP_FILE" ] && break
          printf "\033[s\033[A\r  (%2d sec remaining)\033[u" "$i" > /dev/tty 2>/dev/null || true
      done
    ) &
    local COUNTDOWN_PID=$!
    
    if _timeout 30 sudo -v; then
        touch "$COUNTDOWN_STOP_FILE"
        kill "$COUNTDOWN_PID" 2>/dev/null || true
        wait "$COUNTDOWN_PID" 2>/dev/null || true
        rm -f "$COUNTDOWN_STOP_FILE"
        # sudo always writes "Password:" in this branch (sudo -n failed to get here).
        # After the user interacts, cursor is 2 lines below the countdown line.
        # Go up 2 and erase to end of screen to remove countdown + password lines.
        printf "\033[2A\r\033[J" > /dev/tty 2>/dev/null || true
        echo ""
        return 0
    else
        touch "$COUNTDOWN_STOP_FILE"
        kill "$COUNTDOWN_PID" 2>/dev/null || true
        wait "$COUNTDOWN_PID" 2>/dev/null || true
        rm -f "$COUNTDOWN_STOP_FILE"
        # Cleanup as above for consistency
        printf "\033[2A\r\033[J" > /dev/tty 2>/dev/null || true
        echo ""
        return 1
    fi
}

# Setup sudo credentials and start background refresh process
# Usage: setup_sudo [temp_dir]
# Arguments:
#   temp_dir (optional): Directory to clean up on exit. If provided, enables privileged cleanup.
# Exports:
#   SUDO_AVAILABLE: 1 if sudo credentials available, 0 otherwise
#   SUDO_PROBED: internal compatibility flag; tests should not set or depend on it
#   SUDO_REFRESH_PID: PID of background refresh process (if active)
setup_sudo() {
    local temp_dir="${1:-}"

    # Reset potentially stale inherited sudo state from parent runners.
    unset SUDO_PROBED SUDO_AVAILABLE SUDO_REFRESH_PID
    
    # Define color codes locally (may not be inherited)
    local RED='\033[0;31m'
    local YELLOW='\033[1;33m'
    local NC='\033[0m'
    
    # Probe for sudo credentials.
    SUDO_AVAILABLE=0
    if sudo -n true >/dev/null 2>&1; then
        SUDO_AVAILABLE=1
    elif [ -t 0 ] && [ -t 1 ] && [ -z "${CI:-}" ]; then
        # Both stdin and stdout are connected to a TTY - use interactive countdown prompt
        if _countdown_sudo_prompt "$temp_dir"; then
            SUDO_AVAILABLE=1
        fi
        if [ "$SUDO_AVAILABLE" = "0" ]; then
            echo -e "${YELLOW}No sudo credentials — sudo-dependent tests will be skipped.${NC}"
        fi
    fi
    export SUDO_AVAILABLE SUDO_PROBED=1
    
    # Re-validate runtime sudo state after the initial probe.
    # This handles stale SUDO_AVAILABLE=1 values after credential expiration.
    if [ "${SUDO_AVAILABLE:-0}" = "1" ] && ! sudo -n true >/dev/null 2>&1; then
        SUDO_AVAILABLE=0
        export SUDO_AVAILABLE
    fi

    # If credentials are currently unavailable and we're interactive, try to re-acquire.
    if [ "${SUDO_AVAILABLE:-0}" = "0" ] && [ -t 0 ] && [ -t 1 ] && [ -z "${CI:-}" ]; then
        if _countdown_sudo_prompt "$temp_dir"; then
            SUDO_AVAILABLE=1
            export SUDO_AVAILABLE SUDO_PROBED=1
        fi
    fi

    # Start a background process to refresh sudo credentials while tests run.
    # This prevents credential expiration during test execution.
    # Skip if already running (check if SUDO_REFRESH_PID points to a valid process).
    if [ -z "${SUDO_REFRESH_PID:-}" ] || ! kill -0 "$SUDO_REFRESH_PID" 2>/dev/null; then
        SUDO_REFRESH_PID=""
        if [ "${SUDO_AVAILABLE:-0}" = "1" ]; then
            ( while true; do
                sudo -n true >/dev/null 2>&1 || break
                sleep 30
            done ) &
            SUDO_REFRESH_PID=$!
            disown $SUDO_REFRESH_PID 2>/dev/null || true
        fi
        export SUDO_REFRESH_PID
    fi
    
    # Setup cleanup trap if temp_dir provided and not already set
    # (allows multiple setup_sudo calls without resetting the trap)
    if [ -n "$temp_dir" ] && [ "$(trap -p EXIT | grep -c _sudo_cleanup)" = "0" ]; then
        trap "_sudo_cleanup '$temp_dir'" EXIT
    fi
}

# Check whether sudo credentials are currently active in this process context.
# Usage: ensure_active_sudo
# Returns: 0 if sudo -n works, 1 otherwise
ensure_active_sudo() {
    if sudo -n true >/dev/null 2>&1; then
        SUDO_AVAILABLE=1
        export SUDO_AVAILABLE
        return 0
    fi

    SUDO_AVAILABLE=0
    export SUDO_AVAILABLE
    return 1
}

# Internal cleanup function for trap
# Usage: _sudo_cleanup temp_dir
# Kills the background refresh process and removes the temp directory
_sudo_cleanup() {
    local temp_dir="$1"
    [ -n "$SUDO_REFRESH_PID" ] && kill "$SUDO_REFRESH_PID" >/dev/null 2>&1 || true
    [ -d "$temp_dir" ] && sudo -n rm -rf "$temp_dir" >/dev/null 2>&1 || rm -rf "$temp_dir"
}

export -f setup_sudo
export -f ensure_active_sudo
export -f _sudo_cleanup
