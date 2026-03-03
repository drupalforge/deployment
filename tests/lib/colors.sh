#!/bin/bash
# Shared color/formatting constants for test output.
# Source this file instead of redefining these variables in each test script.
#
# Usage (from a tests/*.sh script that defines TEST_DIR):
#   TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=lib/colors.sh
#   source "$TEST_DIR/lib/colors.sh"
#
# Usage (from tests/lib/*.sh):
#   # shellcheck source=./colors.sh
#   source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"

# Variables are used by scripts that source this file, not within this file itself.
# shellcheck disable=SC2034
RED='\033[0;31m'
# shellcheck disable=SC2034
GREEN='\033[0;32m'
# shellcheck disable=SC2034
YELLOW='\033[1;33m'
# shellcheck disable=SC2034
BLUE='\033[0;34m'
# shellcheck disable=SC2034
NC='\033[0m' # No Color
