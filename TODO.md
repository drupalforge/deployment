# TODO List

## MySQL SSL Certificate Handling

### Investigate proper solution for MySQL 8.0 SSL certificates

**Current workaround:**
Using `--skip-ssl-verify-server-cert` flag in `scripts/import-database.sh` to bypass SSL certificate validation.

**Problem:**
MySQL 8.0 uses SSL by default with self-signed certificates. The MariaDB client in the devpanel/php base image attempts SSL validation and fails with:
```
ERROR 2026 (HY000): TLS/SSL error: self-signed certificate in certificate chain
```

**Why this workaround is not ideal:**
While `--skip-ssl-verify-server-cert` maintains encryption (better than `--skip-ssl`), it bypasses certificate validation entirely. This is a security trade-off appropriate for test/development but not a proper solution.

**Proper solutions to investigate:**
1. **Configure MariaDB client to trust the MySQL self-signed CA**
   - Examine if MySQL 8.0 container provides its CA certificate
   - Configure MariaDB client to use that CA via `--ssl-ca` option
   - This would maintain both encryption AND validation

2. **Check if docker_publish_action solves this differently**
   - They use `devpanel/php:8.3-base-ai` (different base image)
   - May have MySQL client configuration we don't have
   - Investigate what's different in their setup

3. **Consider if GitHub Actions MySQL service has different defaults**
   - GitHub Actions services might configure MySQL differently
   - Test locally with exact same MySQL configuration

**Action items:**
- [ ] Investigate MySQL 8.0 container CA certificate location
- [ ] Test with `--ssl-ca` pointing to MySQL's CA
- [ ] Compare docker_publish_action's base image configuration
- [ ] Document findings and implement proper fix

**References:**
- MySQL SSL docs: https://dev.mysql.com/doc/refman/8.0/en/using-encrypted-connections.html
- MariaDB client SSL options: https://mariadb.com/kb/en/mysql-command-line-client/

---

## Switch back to registry build cache

### Revert GHA cache to `type=registry` in `docker-publish-image.yml`

**File affected:**
- `.github/workflows/docker-publish-image.yml` (`cache-from` / `cache-to` in the "Build and push image" step)

**Background:**
The build cache was switched from `type=registry,mode=max` (Docker Hub) to `type=gha` (GitHub Actions cache) because of two open upstream BuildKit bugs that can cause `COPY` layers to serve stale data, meaning script updates could be silently omitted from published images:

- [moby/buildkit#4817](https://github.com/moby/buildkit/issues/4817) — `COPY` uses stale cached data when file content changes but metadata (filename, size, mtime) is unchanged.
- [moby/buildkit#2279](https://github.com/moby/buildkit/issues/2279) — registry `--cache-from` fails roughly 50% of the time in multi-platform builds.

**Action items:**
- [ ] Monitor moby/buildkit#4817 and moby/buildkit#2279 for fixes
- [ ] Once both issues are resolved, revert `cache-from` and `cache-to` in `.github/workflows/docker-publish-image.yml` back to `type=registry` and remove the `actions: write` permission from the `build-and-push` job and the caller workflow

---

## Platform Specifications

### Remove platform specification from tests when base image supports ARM64

**Files affected:**
- `tests/docker-build-test.sh` (line ~47)
- `tests/docker-compose.test.yml` (line ~70)

**Description:**
Currently, we explicitly specify `--platform linux/amd64` in tests because the devpanel/php base image is not available for linux/arm64. Once the base image supports ARM64:

1. Remove `--platform linux/amd64` from the docker build command in `tests/docker-build-test.sh`
2. Remove `platform: linux/amd64` from the deployment service in `tests/docker-compose.test.yml`

This will allow tests to run natively on any architecture without forcing a specific platform.

**Tracking:**
- Related to devpanel/php base image ARM64 support
- Test on ARM64 systems after removing to ensure compatibility
