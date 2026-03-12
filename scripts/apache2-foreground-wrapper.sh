#!/bin/bash
set -e

# Wrapper for apache2-foreground.
#
# apache-start.sh (DevPanel base image) copies /templates/000-default.conf
# to /etc/apache2/sites-enabled/000-default.conf and substitutes runtime
# variables *before* calling apache2-foreground.  Any proxy rules written
# by setup-proxy.sh during the deployment entrypoint are therefore
# overwritten by that template copy.
#
# Running setup-proxy here — after the template copy and variable
# substitution but before Apache starts — ensures the rewrite rules are
# present in the live vhost config when Apache reads it on startup.
if [ -n "${ORIGIN_URL:-}" ]; then
    # Allow setup-proxy to fail non-fatally: a misconfigured proxy must not
    # prevent Apache from starting.  setup-proxy.sh logs its own errors to
    # stderr, so failures remain visible in the container logs.
    /usr/local/bin/setup-proxy || echo "[apache2-foreground] WARNING: setup-proxy exited non-zero; proxy rules may not be active"
fi

# Original apache2-foreground logic from devpanel/php base image.
# Kept verbatim so the wrapper stays compatible with future base image updates.
: "${APACHE_CONFDIR:=/etc/apache2}"
: "${APACHE_ENVVARS:=$APACHE_CONFDIR/envvars}"
if test -f "$APACHE_ENVVARS"; then
    # shellcheck disable=SC1090
    . "$APACHE_ENVVARS"
fi

# Apache gets grumpy about PID files pre-existing
: "${APACHE_RUN_DIR:=/var/run/apache2}"
: "${APACHE_PID_FILE:=$APACHE_RUN_DIR/apache2.pid}"
rm -f "$APACHE_PID_FILE"

# create missing directories
# (especially APACHE_RUN_DIR, APACHE_LOCK_DIR, and APACHE_LOG_DIR)
for e in "${!APACHE_@}"; do
    if [[ "$e" == *_DIR ]] && [[ "${!e}" == /* ]]; then
        # handle "/var/lock" being a symlink to "/run/lock", but "/run/lock"
        # not existing beforehand, so "/var/lock/something" fails to mkdir
        #   mkdir: cannot create directory '/var/lock': File exists
        dir="${!e}"
        while [ "$dir" != "$(dirname "$dir")" ]; do
            dir="$(dirname "$dir")"
            if [ -d "$dir" ]; then
                break
            fi
            absDir="$(readlink -f "$dir" 2>/dev/null || :)"
            if [ -n "$absDir" ]; then
                mkdir -p "$absDir"
            fi
        done

        mkdir -p "${!e}"
    fi
done

exec apache2 -DFOREGROUND "$@"
