#!/bin/bash
# Shared utility functions for test scripts.

# Portable timeout: prefer system 'timeout' (Linux), then 'gtimeout' (macOS+coreutils),
# then fall back to running the command directly (no time limit; user must press Ctrl-C).
_timeout() {
    local secs="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$secs" "$@"
    else
        "$@"
    fi
}
