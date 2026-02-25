# TODO List

## Remove insecure MySQL skip-verify flag

### Stop adding `--skip-ssl-verify-server-cert` during database import

**Context:**
`scripts/import-database.sh` supports SSL mode controls. The goal is to avoid unconditional skip-verify usage while still allowing an explicit local/test fallback mode when self-signed certificates are unavoidable.

**Done definition:**
- [x] `scripts/import-database.sh` uses client defaults in `compat` and only applies skip-verify in explicit fallback mode
- [x] `README.md` documents current SSL mode behavior clearly
- [x] `bash tests/test-import-database.sh` and `bash tests/unit-test.sh` pass locally
- [x] `bash tests/integration-test.sh` passes locally
- [x] This TODO section is marked complete

**Action items:**
- [x] Update docs for SSL mode behavior without skip-verify
- [x] Make skip-verify fallback explicit (non-default)
- [x] Run relevant tests and mark complete

**Status (2026-02-26): ✅ Complete**

## Consolidate proxy rewrite helper

### Use one helper for proxy rule lifecycle

**Context:**
`scripts/setup-proxy.sh` currently has fragmented and partially broken rewrite manipulation logic. We need one helper that removes existing `drupalforge-proxy-handler` rewrites, ensures a file/dir bypass exists, and injects per-path rewrite rules.

**Done definition:**
- [x] One helper in `scripts/setup-proxy.sh` performs cleanup + bypass ensure + per-path injection
- [x] `configure_apache_proxy()` uses that helper for both `.htaccess` and Apache config targets
- [x] `bash tests/test-setup-proxy.sh` passes locally
- [x] `bash tests/unit-test.sh` passes locally
- [x] `bash tests/integration-test.sh` passes locally
- [x] This TODO section is marked complete

**Status (2026-02-26): ✅ Complete**

**Action items:**
- [x] Add/adjust test assertions for unified helper behavior
- [x] Refactor `setup-proxy.sh` to use one rewrite-update helper
- [x] Move path normalization into unified helper
- [x] Run integration tests and fix regressions

## Stabilize failing test suites

### Restore unit and integration test pass state

**Context:**
Current repository state has failing unit and integration tests. The goal is to identify regressions, apply minimal root-cause fixes, and restore green local test runs.

**Done definition:**
- [x] `bash tests/unit-test.sh` passes locally
- [x] `bash tests/integration-test.sh` passes locally
- [x] Any required code changes include corresponding test/documentation updates
- [x] This TODO section is marked complete after verification

**Status (2026-02-26): ✅ Complete**

Local verification completed successfully:
- `bash tests/unit-test.sh` → all unit suites passed
- `bash tests/integration-test.sh` → 15/15 integration assertions passed

Key completion notes:
- Integration stack remains on MySQL 8.0 with low-memory tuning for Docker Desktop compatibility.
- Secure proxy reliability was restored by preventing startup ordering from allowing later `.htaccess` overwrites in the shared fixture mount.
- Test cleanup and stale-resource removal run before and after integration execution.

**Action items:**
- [x] Run unit tests and capture failures
- [x] Fix root causes for unit failures
- [x] Run integration tests and capture failures
- [x] Fix root causes for integration failures
- [x] Debug deployment-secure readiness timeout
- [x] Fix database import silent failure
- [x] Fix file proxy download failures
- [x] Re-run both suites to verify green

---

## Drupal 11 recommended-project compatibility

### Make DevPanel settings and tests compatible with Drupal 11 minimal install

**Context:**
Current test fixtures use a synthetic database and a minimal fake app, which does not prove Drupal 11 install state detection. `config/settings.devpanel.php` also reads hash salt from a missing file and does not include DB SSL mode controls used by Drush/runtime DB access.

**Done definition:**
- [ ] `config/settings.devpanel.php` derives hash salt deterministically from `$databases` and no longer depends on a missing file
- [ ] Integration fixture database is replaced with a real Drupal 11 minimal-install dump
- [ ] Integration test verifies installer behavior reports Drupal is already installed (no setup flow)
- [ ] MySQL SSL mode is environment-controlled with compatibility mode default and strict mode override for import + Drupal runtime/Drush (implementation aligned with existing "MySQL SSL Certificate Handling" task below)
- [ ] Stage File Proxy behavior is validated against the real Drupal fixture flow
- [ ] README/integration docs reflect new settings and test behavior
- [ ] `bash tests/unit-test.sh`, `bash tests/docker-build-test.sh`, and `bash tests/integration-test.sh` pass locally

**Action items:**
- [ ] Update docs for DB driver requirement, hash salt behavior, and SSL mode controls
- [ ] Add tests for deterministic hash salt and SSL mode behavior
- [ ] Replace fixture DB with a real minimal-install dump and assert installed-state behavior
- [ ] Implement settings/script changes needed to satisfy tests
- [ ] Run full test matrix and mark task complete

---

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
