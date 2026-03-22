ARG PHP_VERSION=8.3
FROM devpanel/php:${PHP_VERSION}-base-rc

# Accept the base image's CMD as a build argument
# Extract before build using: ./extract-base-cmd.sh
ARG BASE_CMD="sudo -E /bin/bash /scripts/apache-start.sh"

# Switch to root for system-level operations
USER root

# Install additional PHP extensions not already provided by the base image.
RUN apt-get update -qq \
    && pecl update-channels \
    && printf '' | pecl install apcu \
    && echo 'extension=apcu.so' > /usr/local/etc/php/conf.d/apcu.ini \
    && printf '' | pecl install uploadprogress \
    && echo 'extension=uploadprogress.so' > /usr/local/etc/php/conf.d/uploadprogress.ini \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI for S3 database import functionality.
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

# Copy startup and deployment scripts
COPY scripts/bootstrap-app.sh /usr/local/bin/bootstrap-app
COPY scripts/import-database.sh /usr/local/bin/import-database
COPY scripts/setup-proxy.sh /usr/local/bin/setup-proxy
COPY scripts/deployment-entrypoint.sh /usr/local/bin/deployment-entrypoint

# Copy Apache configuration for proxy and PHP proxy handler
COPY config/apache-proxy.conf /etc/apache2/conf-available/drupalforge-proxy.conf
COPY config/settings.devpanel.php /var/www/settings.devpanel.php
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
# Use bash -c so BASE_CMD (an ENV variable) is expanded at runtime and forwarded
# as a proper argv command for deployment-entrypoint's final `exec "$@"`.
# Do NOT use -l (login shell) here: a login shell sources /etc/profile and user
# profile scripts, which in the DevPanel base image initialize VS Code Server.
# The base image exclusively uses $APP_ROOT/.vscode as the VS Code user data
# directory. APP_ROOT is injected at runtime by DevPanel, so it is not available
# when a login shell runs before APP_ROOT has been set (for example, at initial
# container startup). Without APP_ROOT, VS Code Server falls back to its default
# home-directory path (/home/www/.vscode-server), creating that directory in the
# container's writable layer. Removing -l prevents profile scripts from running,
# which prevents VS Code Server from initializing prematurely and creating the
# unwanted /home/www/.vscode-server directory.
# This covers:
# 1) normal startup using the base-image Apache command,
# 2) command strings that depend on env expansion,
# 3) predictable behavior with exec-form ENTRYPOINT while still allowing
#    runtime CMD overrides (e.g. `docker run ... <command>`).
CMD ["/bin/bash", "-c", "$BASE_CMD"]

LABEL org.opencontainers.image.source="https://github.com/drupalforge/deployment" \
      org.opencontainers.image.description="Drupal Forge deployment image with S3 database import and conditional file proxy support"
