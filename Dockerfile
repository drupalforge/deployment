ARG PHP_VERSION=8.3
FROM devpanel/php:${PHP_VERSION}-base

# Accept the base image's CMD as a build argument
# Extract before build using: ./extract-base-cmd.sh
ARG BASE_CMD="sudo -E /bin/bash /scripts/apache-start.sh"

# Switch to root for system-level operations
USER root

# Install AWS CLI for S3 database import functionality
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        awscli \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy startup and deployment scripts
COPY scripts/bootstrap-app.sh /usr/local/bin/bootstrap-app
COPY scripts/import-database.sh /usr/local/bin/import-database
COPY scripts/setup-proxy.sh /usr/local/bin/setup-proxy
COPY scripts/deployment-entrypoint.sh /usr/local/bin/deployment-entrypoint

# Copy Apache configuration for proxy and PHP proxy handler
COPY config/apache-proxy.conf /etc/apache2/conf-available/drupalforge-proxy.conf
COPY scripts/proxy-handler.php /var/www/drupalforge-proxy-handler.php

# Enable Apache proxy and rewrite modules for conditional file serving
# Requests for missing files are routed to PHP handler which downloads to expected path
RUN a2enmod proxy && \
    a2enmod proxy_http && \
    a2enmod rewrite && \
    a2enconf drupalforge-proxy || true

# Create $WEB_ROOT (default: /var/www/html/web) so the startup wait loop sees a non-empty APP_ROOT
# when no volume is mounted (e.g. during image build/smoke tests)
RUN mkdir -p /var/www/html/web

# Switch back to non-root user for runtime
# Use USER environment variable from base image
USER ${USER}

# Make BASE_CMD available as environment variable
ENV BASE_CMD="${BASE_CMD}"

# Use ENTRYPOINT to ensure deployment setup always runs
ENTRYPOINT ["/usr/local/bin/deployment-entrypoint"]

# Set CMD from base image (passed as build arg)
CMD $BASE_CMD

LABEL org.opencontainers.image.source="https://github.com/drupalforge/deployment" \
      org.opencontainers.image.description="Drupal Forge deployment image with S3 database import and conditional file proxy support"
