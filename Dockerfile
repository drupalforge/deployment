ARG PHP_VERSION=8.3
FROM devpanel/php:${PHP_VERSION}-base

# Accept the base image's CMD as a build argument
# Extract before build using: ./extract-base-cmd.sh
ARG BASE_CMD="sudo -E /bin/bash /scripts/apache-start.sh"

# Switch to root for system-level operations
USER root

# Install AWS CLI for S3 database import functionality.
# curl and unzip are already provided by the base image.
RUN arch="$(dpkg --print-architecture)" \
    && case "${arch}" in \
        amd64) aws_arch="x86_64" ;; \
        arm64) aws_arch="aarch64" ;; \
        *) echo "Unsupported architecture for AWS CLI: ${arch}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip

# Configure MariaDB client to accept server SSL certificates from managed databases.
# DigitalOcean and similar providers use a self-signed CA not in the system truststore;
# SSL encryption is still used, but certificate chain validation is skipped.
# /etc/mysql/conf.d/ is provided by the base image; no mkdir needed.
COPY config/mariadb-client.cnf /etc/mysql/conf.d/drupalforge.cnf

# Copy startup and deployment scripts
COPY scripts/bootstrap-app.sh /usr/local/bin/bootstrap-app
COPY scripts/import-database.sh /usr/local/bin/import-database
COPY scripts/setup-proxy.sh /usr/local/bin/setup-proxy
COPY scripts/deployment-entrypoint.sh /usr/local/bin/deployment-entrypoint

# Copy Apache configuration for proxy and PHP proxy handler
COPY config/apache-proxy.conf /etc/apache2/conf-available/drupalforge-proxy.conf
COPY config/settings.devpanel.php /usr/local/share/drupalforge/settings.devpanel.php
COPY scripts/proxy-handler.php /var/www/drupalforge-proxy-handler.php

# Enable Apache proxy and rewrite modules for conditional file serving
# Requests for missing files are routed to PHP handler which downloads to expected path
RUN a2enmod proxy && \
    a2enmod proxy_http && \
    a2enmod rewrite && \
    a2enconf drupalforge-proxy || true

# Switch back to non-root user for runtime
# Use USER environment variable from base image
USER ${USER}

# APP_ROOT (/var/www/html) must be owned by the container user, not root.
# Chown it and create the default WEB_ROOT in a single step; once we own the
# parent directory, install -d needs no sudo.
RUN sudo chown "${USER}:${USER}" /var/www/html && \
    install -d /var/www/html/web

# Make BASE_CMD available as environment variable
ENV BASE_CMD="${BASE_CMD}"

# Use ENTRYPOINT to ensure deployment setup always runs
ENTRYPOINT ["/usr/local/bin/deployment-entrypoint"]

# Set CMD from base image (passed as build arg)
# Use bash -lc so BASE_CMD is expanded at runtime and forwarded as a proper
# argv command for deployment-entrypoint's final `exec "$@"`.
# This covers:
# 1) normal startup using the base-image Apache command,
# 2) command strings that depend on env expansion,
# 3) predictable behavior with exec-form ENTRYPOINT while still allowing
#    runtime CMD overrides (e.g. `docker run ... <command>`).
CMD ["/bin/bash", "-lc", "$BASE_CMD"]

LABEL org.opencontainers.image.source="https://github.com/drupalforge/deployment" \
      org.opencontainers.image.description="Drupal Forge deployment image with S3 database import and conditional file proxy support"
