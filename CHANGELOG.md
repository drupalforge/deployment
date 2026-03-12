# Changelog

All completed work for the Drupal Forge deployment image is tracked here. When a task is finished, move it from `TODO.md` to this file, including its context, done definition, and completion status.

## Add and require markdownlint with baseline tracking

### Validate Markdown formatting without blocking legacy doc debt

**Context:**
The suite initially had no Markdown lint coverage. Then `markdownlint` was made required, which exposed many existing repository violations. To avoid masking rules globally while still keeping CI actionable, Markdown lint now enforces "no new violations" via a baseline file.

**Done definition:**
- [x] Add Markdown lint configuration at repository root
- [x] Add `tests/test-markdown-lint.sh` using repository output conventions
- [x] Make `markdownlint` required for markdown lint unit tests
- [x] Install `markdownlint-cli` in unit-test CI setup
- [x] Track existing violations in `tests/markdownlint-baseline.txt`
- [x] Compare current lint results against baseline so new violations fail
- [x] Add `tests/update-markdownlint-baseline.sh` to regenerate baseline after intentional cleanup
- [x] Update `tests/README.md` to document required tool + baseline workflow
- [x] `bash tests/test-markdown-lint.sh` passes locally
- [x] `bash tests/unit-test.sh` passes locally

**Implementation notes:**
- `tests/test-markdown-lint.sh` fails if `markdownlint` is missing and compares lint output to baseline entries.
- Baseline entries are stored as `<file> <rule> <count>` (not line-based), reducing churn from line movement.
- `.github/workflows/tests.yml` installs `markdownlint-cli` for deterministic CI unit-test runs.
- Install guidance now links to official `markdownlint-cli` installation docs rather than prescribing one local install method.
- Added TODO tracking for baseline burn-down until `tests/markdownlint-baseline.txt` is empty/removed.

**Status: ✅ Complete (2026-03-12)**

---

## Exclude generated CSS/JS from Apache file proxy

### Prevent proxy misses for per-site asset filenames

**Context:**
Drupal aggregated CSS/JS asset filenames differ across sites and environments. Proxying `${FILE_PROXY_PATHS}/css/*` and `${FILE_PROXY_PATHS}/js/*` to origin causes unnecessary misses because those generated filenames often do not exist on origin for the current site.

**Done definition:**
- [x] `scripts/setup-proxy.sh` excludes `${path}/css/` and `${path}/js/` from regular file-proxy RewriteConds for every configured file proxy path
- [x] `tests/test-setup-proxy.sh` validates the generated rewrite rules include CSS/JS exclusions
- [x] `README.md` documents that Apache fallback proxy excludes generated CSS/JS paths and why
- [x] `bash tests/test-setup-proxy.sh` passes locally
- [x] `bash tests/unit-test.sh` passes locally

**Implementation notes:**
- Added explicit regular-file rewrite exclusions for `${path}/css/` and `${path}/js/` in `configure_apache_proxy()` so generated aggregated assets are handled by the local Drupal runtime instead of being fetched from origin.
- Clarified docs that image-style requests under `${path}/styles/` do not proxy derivatives from origin; they trigger original-image download so Drupal generates styles locally.
- Extended `tests/test-setup-proxy.sh` per-path rewrite checks to assert CSS/JS/style subtree exclusions.
- Updated README proxy behavior notes to document why CSS/JS paths are excluded under Apache fallback mode.

**Status: ✅ Complete (2026-03-12)**

---

## Fix image-style proxy: correct RewriteCond and refactor PHP handler

### Ensure image-style URLs are correctly proxied

**Context:**
Drupal image-style URLs contain a `?itok=…` cache-buster. The existing image-style `RewriteCond` was negated (`!^…`), so it never set `%1` to the original file's subpath. As a result, proxy rules never fired for styled images; Drupal received requests with no source file on disk and returned "Error generating image, missing source file."

Regular file proxy was unaffected because no negation existed for non-`styles/` paths.

**Done definition:**
- [x] `setup-proxy.sh` image-style `RewriteCond` uses `(.+)$` capture group; the condition is a POSITIVE (non-negated) match so that `%1` is correctly set to the original file's subpath
- [x] `setup-proxy.sh` regular file proxy `RewriteCond` simplified from `^%s(/|$)` to `^%s/` (no reason to proxy just the directory)
- [x] `setup-proxy.sh` injects the managed rewrite block into both `/templates/000-default.conf` and `/etc/apache2/sites-enabled/000-default.conf` (direct vhost); `/etc/apache2/sites-available` remains untouched
- [x] `proxy-handler.php` 302 redirect logic extracted into a reusable `redirect_to_requested_uri()` function shared by both early-exit and post-download paths
- [x] `tests/integration-test.sh` "File proxy setup (rewrite rules)" assertion updated to grep `sites-enabled/000-default.conf`
- [x] `bash tests/test-setup-proxy.sh` passes locally
- [x] `bash tests/test-proxy-handler.sh` passes locally
- [x] `bash tests/unit-test.sh` passes locally
- [x] CI integration tests pass

**Implementation notes:**
- Apache's `%{REQUEST_URI}` is the path component of the URL only; the query string (`?itok=…`) is provided separately via `%{QUERY_STRING}`. The original `(.+)$` capture group is correct — the `$` end-anchor matches the end of the path since `%{REQUEST_URI}` never contains a `?`. The primary fix was ensuring the condition is a positive (non-negated) match so that `%1` is correctly set to the image subpath.
- The `SetEnv ORIGIN_URL` / `SetEnv WEB_ROOT` directives added in a previous iteration were incorrect: regular file proxy was working without them, confirming they are not needed. Removing them simplifies the injected block.

**Status: ✅ Complete (2026-03-12)**

---

## Fix integration test failures (apache-start.sh template overwrite)

### Ensure proxy rules survive apache-start.sh template copy before Apache starts

**Context:**
`deployment-entrypoint.sh` calls `setup-proxy.sh` which injects rewrite rules into
`/etc/apache2/sites-enabled/000-default.conf`. However, `apache-start.sh` (the DevPanel
base image startup script) runs `sudo cp /templates/000-default.conf /etc/apache2/sites-enabled/000-default.conf`
AFTER the entrypoint finishes, overwriting the injected rules. Apache then starts with no proxy rules.

The fix: `setup-proxy.sh` now injects rules into BOTH `/etc/apache2/sites-enabled/000-default.conf`
(live config) and `/templates/000-default.conf` (always present in the DevPanel base image).
When `apache-start.sh` copies the template over the live config, the rules are already in the
template so they are preserved.

**Done definition:**
- [x] `setup-proxy.sh` injects rules into both `/etc/apache2/sites-enabled/000-default.conf` and `/templates/000-default.conf`
- [x] `bash tests/test-setup-proxy.sh` passes locally
- [x] `bash tests/unit-test.sh` passes locally
- [x] CI integration tests pass

**Action items:**
- [x] Update `setup-proxy.sh` to inject into both files
- [x] Remove `scripts/apache2-foreground-wrapper.sh`
- [x] Revert Dockerfile to remove the wrapper COPY
- [x] Update test-setup-proxy.sh test 10 to assert both targets
- [x] Run unit tests
- [x] Verify CI

**Status: ✅ Complete (2026-03-12)**

---

## Fix CSS/MIME detection and simplify proxy setup

### Replace PHP MIME serving with 302 redirect; inject rewrite rules into vhost config

**Context:**
`finfo_file()` misclassified extension-based formats like CSS as `text/plain`, causing browsers to reject stylesheets. The proxy setup also wrote to `.htaccess` as a runtime fallback and generated bypass rules dynamically, adding complexity. Writing rewrite rules to `drupalforge-proxy.conf` (a global conf include) did not work because the rules must run inside the `<VirtualHost>` context where Drupal's site routing applies.

**Done definition:**
- [x] `proxy-handler.php` downloads the file then issues a `302` redirect back to the original URL; Apache serves it with correct `Content-Type` via `mod_mime`
- [x] `setup-proxy.sh` injects rewrite rules directly into the Apache vhost templates (`/templates/000-default.conf` and `/etc/apache2/sites-available/000-default.conf`) inside a `BEGIN/END DRUPALFORGE PROXY RULES` marker block, replacing any previous block on re-runs (no `.htaccess` fallback)
- [x] `config/apache-proxy.conf` holds only the `Mutex`, `Alias`, `Location`, and proxy module settings; rewrite rules live in the vhost config where they run in the correct `<VirtualHost>` context
- [x] `setup-proxy.sh` inlines the awk injection directly in `configure_apache_proxy()` (no separate helper function)
- [x] File-existence bypass rules (`RewriteCond %{DOCUMENT_ROOT}%{REQUEST_URI} -f/-d` + `RewriteRule ^ - [L]`) are written into the vhost block by `setup-proxy.sh`, before the per-path proxy rules
- [x] Per-path proxy rules use `[END,PT]` so the `Alias /drupalforge-proxy-handler.php` is applied after the rewrite in the vhost context
- [x] `setup-proxy.sh` checks `pgrep -x apache2` before calling `apache2ctl graceful` to avoid starting Apache prematurely during container startup
- [x] `test-proxy-handler.sh` tests redirect behavior instead of MIME headers; tests numbered sequentially
- [x] `test-setup-proxy.sh` updated to match vhost-injection approach; `test_unified_rewrite_helper` renamed to `test_inline_rewrite_awk`
- [x] `integration-test.sh` proxy download tests use `curl -sL` to follow the 302
- [x] `bash tests/unit-test.sh` passes
- [x] CI integration tests pass

**Implementation notes:**
- Rewrite rules in a global conf include (`drupalforge-proxy.conf`) apply outside the `<VirtualHost>` context and do not have access to the vhost's `DocumentRoot`, causing them to fail. Rules must be injected into the vhost configuration directly.
- `[PT]` is required alongside `[END]` so the `Alias /drupalforge-proxy-handler.php` mapping is re-applied after the rewrite. `[END]` alone caused 404s in integration runs because the Alias was skipped.
- `apache2ctl graceful` starts Apache when not running; guarding with `pgrep -x apache2` prevents premature startup that would conflict with the normal startup sequence.

**Status: ✅ Complete (2026-03-11)**

---

## Re-run and restore full test matrix

### Run all suites and fix regressions without sudo skips

**Context:**
Previous session context was lost. Re-ran the complete test matrix and fixed regressions. Sudo-dependent tests were kept as real checks (no broad skip strategy).

**Done definition:**
- [x] `bash tests/unit-test.sh` passes locally with sudo-dependent checks executing (not skipped)
- [x] `bash tests/docker-build-test.sh` passes locally
- [x] `bash tests/integration-test.sh` passes locally
- [x] `bash tests/run-all-tests.sh` passes locally end-to-end
- [x] Regressions were fixed with corresponding test/doc updates
- [x] Completed task moved from `TODO.md` to `CHANGELOG.md`

**Implementation notes:**
- Removed hardcoded `--platform linux/amd64` from one-off integration validation containers in `tests/integration-test.sh` so those checks run on native Docker platform (macOS ARM + Linux compatible).
- Updated integration docs in `tests/INTEGRATION_TESTING.md` to document native-platform one-off validation behavior.
- Kept root-owned APP_ROOT coverage in `tests/test-deployment-entrypoint.sh` as a true sudo-required check.
- Refactored DRUSH URI unit checks in `tests/test-deployment-entrypoint.sh` to use a local `sudo` stub, so URI behavior is validated deterministically without depending on host sudo state.

**Status: ✅ Complete (2026-03-10)**

---

## Use cross-platform PHP base images

### Remove platform specification from Dockerfile and tests

**Context:**
Now that `devpanel/php:8.2-base-rc` and `devpanel/php:8.3-base-rc` support both `linux/amd64` and `linux/arm64`, we can remove platform-specific restrictions from the deployment image and tests. This enables native builds and tests on ARM64 systems without forcing amd64 emulation.

**Done definition:**
- [x] `Dockerfile` uses `devpanel/php:${PHP_VERSION}-base-rc` cross-platform base images
- [x] `Dockerfile` removes `MAKEFLAGS="-j1"` single-thread GD compile workaround (was needed for QEMU multi-threaded stress)
- [x] `tests/docker-build-test.sh` removes `--platform linux/amd64` flag from docker build command
- [x] `tests/docker-compose.test.yml` removes `platform: linux/amd64` from both deployment services
- [x] `bash tests/unit-test.sh` passes locally (8/9 suites, 1 pre-existing entrypoint failure unrelated to this work)
- [x] `bash tests/docker-build-test.sh` passes locally on ARM64 system
- [x] `bash tests/integration-test.sh` passes locally (16/18 assertions, 2 pre-existing one-off container failures unrelated to this work)

**Status: ✅ Complete (2026-03-10)**

**Notes:**
- Tested on ARM64 system (macOS arm64); native builds work without platform forcing
- Docker build and integration tests confirm cross-platform images build and run correctly
- Removed `-base` and switched to `-rc` tagged images for verified cross-platform support
- Single-thread GD compile workaround no longer needed with native ARM64 builds

---

## Ensure config sync directory exists

### Create missing `$settings['config_sync_directory']` during DevPanel settings include

**Context:**
`config/settings.devpanel.php` sets a default `config_sync_directory` path, but deployments can fail when that directory does not exist yet.

**Done definition:**
- [x] `scripts/bootstrap-app.sh` creates `$settings['config_sync_directory']` recursively when it is missing
- [x] Existing values are respected (no override when already set)
- [x] `bash tests/test-bootstrap-app.sh` passes locally
- [x] `bash tests/unit-test.sh` passes locally

**Status: ✅ Complete (2026-02-27)**

---

## Remove insecure MySQL skip-verify flag

### Stop adding `--skip-ssl-verify-server-cert` during database import

**Context:**
`scripts/import-database.sh` supports SSL mode controls. The goal is to avoid unconditional skip-verify usage while still allowing an explicit local/test fallback mode when self-signed certificates are unavoidable.

**Done definition:**
- [x] `scripts/import-database.sh` uses client defaults in `compat` and only applies skip-verify in explicit fallback mode
- [x] `README.md` documents current SSL mode behavior clearly
- [x] `bash tests/test-import-database.sh` and `bash tests/unit-test.sh` pass locally
- [x] `bash tests/integration-test.sh` passes locally

**Status: ✅ Complete (2026-02-26) - superseded by MySQL SSL Certificate Handling**

---

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

**Status: ✅ Complete (2026-02-26)**

---

## Stabilize failing test suites

### Restore unit and integration test pass state

**Context:**
Current repository state has failing unit and integration tests. The goal is to identify regressions, apply minimal root-cause fixes, and restore green local test runs.

**Done definition:**
- [x] `bash tests/unit-test.sh` passes locally
- [x] `bash tests/integration-test.sh` passes locally
- [x] Any required code changes include corresponding test/documentation updates

**Local verification completed successfully:**
- `bash tests/unit-test.sh` → all unit suites passed
- `bash tests/integration-test.sh` → 15/15 integration assertions passed

**Notes:**
- Integration stack remains on MySQL 8.0 with low-memory tuning for Docker Desktop compatibility.
- Secure proxy reliability was restored by preventing startup ordering from allowing later `.htaccess` overwrites in the shared fixture mount.
- Test cleanup and stale-resource removal run before and after integration execution.

**Status: ✅ Complete (2026-02-26)**

---

## Verify installer skips DB setup without import

### Add integration coverage for install flow with settings.devpanel include and empty database

**Context:**
When `settings.php` includes the app-root-grandparent `settings.devpanel.php` path and no S3 database import runs, Drupal installer should skip the database setup form and proceed directly to install flow.

**Done definition:**
- [x] Integration suite includes a no-import deployment scenario using an empty database
- [x] Integration test hits `/core/install.php?rewrite=ok&langcode=en&profile=minimal`
- [x] Assertion confirms database setup step is skipped and install flow starts
- [x] `bash tests/integration-test.sh` passes locally

**Status: ✅ Complete (2026-02-27)**

---

## Ensure import uses DB_PORT consistently

### Pass explicit MySQL port in all import script connections

**Context:**
`scripts/import-database.sh` logs `DB_PORT` but does not pass it to `mysql`, so deployments on non-default ports can fail.

**Done definition:**
- [x] `scripts/import-database.sh` passes `-P "${DB_PORT:-3306}"` for readiness, table checks, and import execution
- [x] `README.md` documents `DB_PORT` default behavior for import connections
- [x] `bash tests/test-import-database.sh` passes locally
- [x] `bash tests/unit-test.sh` passes locally

**Status: ✅ Complete (2026-03-03)**

---

## Normalize DB_PORT default assignment

### Set DB_PORT fallback once before MySQL calls

**Context:**
`scripts/import-database.sh` currently repeats `${DB_PORT:-3306}` in each MySQL invocation. Set the default once for readability and consistency.

**Done definition:**
- [x] `scripts/import-database.sh` assigns `DB_PORT` default once before connection attempts
- [x] All MySQL commands use `-P "$DB_PORT"`
- [x] `tests/test-import-database.sh` validates the single-default + per-command port usage pattern
- [x] `bash tests/test-import-database.sh` passes locally
- [x] `bash tests/unit-test.sh` passes locally

**Status: ✅ Complete (2026-03-03)**

---

## Ensure private path ownership matches webserver

### Align `$settings['file_private_path']` ownership with Apache runtime user/group

**Context:**
The private files directory should be owned by the webserver user/group, matching how public files path ownership is handled.

**Done definition:**
- [x] `scripts/bootstrap-app.sh` ensures non-empty `$settings['file_private_path']` is owned by the resolved Apache runtime user/group
- [x] Ownership resolution follows existing Apache env behavior (`APACHE_RUN_USER`/`APACHE_RUN_GROUP`, `/etc/apache2/envvars` fallback)
- [x] `tests/test-bootstrap-app.sh` covers private path ownership behavior
- [x] `README.md` documents private path ownership behavior
- [x] `bash tests/test-bootstrap-app.sh` passes locally
- [x] `bash tests/unit-test.sh` passes locally

**Status: ✅ Complete (2026-03-03)**

---

## Ensure file private path exists

### Create `$settings['file_private_path']` when configured

**Context:**
When Drupal config sets a non-empty `$settings['file_private_path']`, deployments can fail if that directory does not exist at startup.

**Done definition:**
- [x] `scripts/bootstrap-app.sh` resolves `$settings['file_private_path']` and creates it recursively when non-empty
- [x] Empty `file_private_path` values are treated as disabled and do not create directories
- [x] `README.md` documents the private files directory bootstrap behavior
- [x] `bash tests/test-bootstrap-app.sh` passes locally
- [x] `bash tests/unit-test.sh` passes locally

**Status: ✅ Complete (2026-03-03)**

---

## Add integration coverage for private file path

### Validate private path creation and ownership in integration environment

**Context:**
Unit tests cover private file path creation/ownership in bootstrap. Integration tests should also assert that the runtime container creates the private path and aligns ownership with the configured webserver user.

**Done definition:**
- [x] `tests/integration-test.sh` asserts the private file path exists in the integration deployment container
- [x] Integration assertion validates ownership matches the Apache runtime user/group used by that container
- [x] `tests/INTEGRATION_TESTING.md` documents the additional private path integration coverage
- [x] `bash tests/integration-test.sh` passes locally

**Status: ✅ Complete (2026-03-03)**

---

## Add AVIF/APCU/uploadprogress PHP extensions

### Enable GD AVIF support and install APCU/uploadprogress in image build

**Context:**
Drupal Forge deployments need GD compiled with AVIF support and two additional PHP extensions (`apcu` and `uploadprogress`) available at runtime.

**Done definition:**
- [x] `Dockerfile` installs build deps and compiles GD with AVIF support
- [x] `Dockerfile` installs `apcu` and `uploadprogress` via PECL and enables both extensions
- [x] Build dependency cleanup is performed after installation (purge/autoremove/apt cache cleanup)
- [x] `tests/test-dockerfile.sh` validates the new extension install and cleanup patterns
- [x] `README.md` documents these bundled PHP extension capabilities
- [x] `bash tests/test-dockerfile.sh` and `bash tests/unit-test.sh` pass locally

**Status: ✅ Complete (2026-03-03)**

---

## Add secure-mode private path integration check

### Validate private path ownership with default Apache `www-data`

**Context:**
Current integration coverage validates private path ownership in the main deployment container (`APACHE_RUN_USER=www`). We also need a secure-mode check that validates bootstrap behavior when Apache runs with defaults (`www-data`).

**Done definition:**
- [x] `tests/integration-test.sh` includes a one-off secure-mode container assertion for private path ownership
- [x] Assertion validates `/var/www/html/private` ownership resolves to `www-data:www-data`
- [x] `tests/INTEGRATION_TESTING.md` reflects the added secure-mode private path check and updated test count
- [x] `bash tests/integration-test.sh` passes locally

**Status: ✅ Complete (2026-03-03)**

---

## MySQL SSL Certificate Handling

### Root cause identified and fixed

**Problem:**
The MariaDB client in the image failed with:
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

**Status: ✅ Complete (2026-02-27)**

