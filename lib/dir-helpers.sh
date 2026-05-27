#!/bin/bash
# Shared directory helper functions for deployment scripts
# create_dirs_owned_by_owner DIR OWNER_USER OWNER_GROUP
# Creates all missing path components under DIR. Tries to `mkdir -p` as
# the invoking user first; if that doesn't yield the desired ownership,
# creates missing components via `sudo -n install -d -o OWNER -g GROUP`.

set -e

create_dirs_owned_by_owner() {
  local dir="$1"
  local owner_user="$2"
  local owner_group="$3"
  local p
  local -a parts
  local IFS='/'

  if mkdir -p -- "$dir" 2>/dev/null; then
    if [ -d "$dir" ]; then
      local current_spec
      current_spec="$(stat -c '%U:%G' "$dir" 2>/dev/null || stat -f '%Su:%Sg' "$dir" 2>/dev/null || true)"
      if [ "$current_spec" = "${owner_user}:${owner_group}" ]; then
        return 0
      fi
    fi
  fi

  read -ra parts <<< "$dir"

  if [[ "$dir" = /* ]]; then
    p="/"
  else
    p=""
  fi

  for part in "${parts[@]}"; do
    [ -z "$part" ] && continue
    if [ -z "$p" ] || [ "$p" = "/" ]; then
      p="${p}${part}"
    else
      p="${p%/}/$part"
    fi
    if [ ! -d "$p" ]; then
      sudo -n install -d -o "$owner_user" -g "$owner_group" "$p"
    fi
  done
}

export -f create_dirs_owned_by_owner

# Wrapper for scripts that want to create dirs owned by the invoking user.
create_dirs_owned_by_current_user() {
  create_dirs_owned_by_owner "$1" "$(id -un)" "$(id -gn)"
}

export -f create_dirs_owned_by_current_user
