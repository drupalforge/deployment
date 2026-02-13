ARG PHP_VERSION=8.3
FROM devpanel/php:${PHP_VERSION}-base

# Switch to root for system-level operations
USER root

# Copy startup and deployment scripts
COPY scripts/bootstrap-app.sh /usr/local/bin/bootstrap-app
COPY scripts/import-database.sh /usr/local/bin/import-database
COPY scripts/setup-proxy.sh /usr/local/bin/setup-proxy
COPY scripts/deployment-entrypoint.sh /usr/local/bin/deployment-entrypoint

# Copy Apache configuration for proxy and PHP proxy handler
COPY config/apache-proxy.conf /etc/apache2/conf-available/drupalforge-proxy.conf
COPY proxy-handler.php /var/www/drupalforge-proxy-handler.php

# Enable Apache proxy and rewrite modules for conditional file serving
# Requests for missing files are routed to PHP handler which downloads to expected path
RUN a2enmod proxy && \
    a2enmod proxy_http && \
    a2enmod rewrite && \
    a2enconf drupalforge-proxy || true

# Switch back to non-root user for runtime
USER ${USER}

# Use ENTRYPOINT to ensure deployment setup always runs
ENTRYPOINT ["/usr/local/bin/deployment-entrypoint"]

LABEL org.opencontainers.image.source="https://github.com/drupalforge/deployment" \
      org.opencontainers.image.description="Drupal Forge deployment image with S3 database import and conditional file proxy support"
