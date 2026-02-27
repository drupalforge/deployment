# TODO List

## Verify installer skips DB setup without import

### Add integration coverage for install flow with settings.devpanel include and empty database

**Context:**
When `settings.php` includes `/usr/local/share/drupalforge/settings.devpanel.php` and no S3 database import runs, Drupal installer should skip the database setup form and proceed directly to install flow.

**Done definition:**
- [x] Integration suite includes a no-import deployment scenario using an empty database
- [x] Integration test hits `/core/install.php?rewrite=ok&langcode=en&profile=minimal`
- [x] Assertion confirms database setup step is skipped and install flow starts
- [x] `bash tests/integration-test.sh` passes locally
- [x] This TODO section is marked complete

**Action items:**
- [x] Document the new integration scenario in test docs
- [x] Add no-import deployment scenario to compose test stack
- [x] Add installer-flow assertion in integration test script
- [x] Run integration tests and mark complete

**Status (2026-02-27): ✅ Complete**

## Ensure config sync directory exists

### Create missing `$settings['config_sync_directory']` during DevPanel settings include

**Context:**
`config/settings.devpanel.php` sets a default `config_sync_directory` path, but deployments can fail when that directory does not exist yet.

**Done definition:**
- [x] `scripts/bootstrap-app.sh` creates `$settings['config_sync_directory']` recursively when it is missing
- [x] Existing values are respected (no override when already set)
- [x] `bash tests/test-bootstrap-app.sh` passes locally
- [x] `bash tests/unit-test.sh` passes locally
- [x] This TODO section is marked complete

**Action items:**
- [x] Document the new behavior in `README.md`
- [x] Add/update unit tests for missing directory creation
- [x] Implement directory creation in `scripts/bootstrap-app.sh`
- [x] Run relevant tests and mark task complete

**Status (2026-02-27): ✅ Complete**

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

**Status (2026-02-26): ✅ Complete (superseded — see MySQL SSL Certificate Handling below)**

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

### Root cause identified and fixed

**Problem:**
The MariaDB client in our image failed with:
```
ERROR 2026 (HY000): TLS/SSL error: self-signed certificate in certificate chain
```
when connecting to MySQL 8.0 (integration tests) and cloud-managed databases (e.g. DigitalOcean).

**Root cause (confirmed by comparison with `drupalforge/drupal-11:latest`):**
`devpanel/php:8.3-base` uses **MariaDB 11.8.3**, which changed the default of
`ssl-verify-server-cert` from `FALSE` (MariaDB 10.x) to `TRUE`. The
`drupalforge/drupal-11:latest` image uses MariaDB 10.11.11 and connects to
MySQL 8.0 without any configuration because `ssl-verify-server-cert` still
defaults to `FALSE` in that version.

Both images have `ssl = TRUE` (SSL required for TCP connections). The only
difference is whether the server certificate chain is validated. Neither image
can connect if SSL is disabled on the server side — the client rejects that too.

**Fix:**
Added `config/mariadb-client.cnf` (copied via Dockerfile to
`/etc/mysql/conf.d/drupalforge.cnf`) with `ssl-verify-server-cert = off` under
`[client]`. This restores the MariaDB 10.x default: SSL encryption is kept
active but certificate chain validation is disabled, which is appropriate for
MySQL 8.0 (self-signed cert) and cloud-managed databases (private CA).

**Done definition:**
- [x] `Dockerfile` no longer reinstalls `curl` over the base image's version
- [x] `config/mariadb-client.cnf` sets `ssl-verify-server-cert = off` under `[client]`
- [x] `Dockerfile` copies `config/mariadb-client.cnf` to `/etc/mysql/conf.d/drupalforge.cnf`
- [x] `MYSQL_SSL_MODE`/`MYSQL_SSL_CA` workaround removed from `scripts/import-database.sh`
- [x] `--skip-ssl-verify-server-cert` flags removed from `scripts/import-database.sh`
- [x] Corresponding workaround tests removed from `tests/test-import-database.sh`
- [x] `README.md` no longer documents `MYSQL_SSL_MODE`/`MYSQL_SSL_CA`
- [x] `tests/test-dockerfile.sh` verifies the COPY directive and config file content
- [x] `bash tests/unit-test.sh` passes locally
- [x] This TODO section is marked complete

**Status (2026-02-27): ✅ Complete**

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
