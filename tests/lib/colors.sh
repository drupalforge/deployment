#!/bin/bash
# shellcheck disable=SC2034  # Variables are used by scripts that source this file, not within this file itself.
# Shared color/formatting constants for test output.
# Source this file instead of redefining these variables in each test script.
#
# Usage (from a tests/*.sh script):
#   TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   SCRIPT_DIR="${TEST_DIR%/*}"
#   # shellcheck source=lib/colors.sh
#   source "$TEST_DIR/lib/colors.sh"
#
# Usage (from tests/lib/*.sh that defines LIB_DIR):
#   LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=./colors.sh
#   source "$LIB_DIR/colors.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
