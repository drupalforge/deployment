# TODO List

## Fix integration tests failing on retired MinIO images

**Context:** [Integration job 120113548672](https://github.com/drupalforge/deployment/actions/runs/39860508216/job/120113548672) cannot pull `minio/minio` and `minio/mc`; the integration environment then fails to start.

**Status:** Implementation complete; CI validation is awaiting approval. The local end-to-end run stops during the image build because this environment cannot resolve PECL hosts.

**Done definition:**

- [x] Document Adobe S3Mock as the S3-compatible mock used by integration tests.
- [x] Add regression checks for its Compose configuration and fixture upload.
- [x] Replace unavailable MinIO images and verify setup with focused tests and an AWS CLI/S3Mock smoke test.
- [x] Record local integration limitation: image build fails before startup because DNS cannot resolve `pecl.php.net` and `doc.php.net`.
- [ ] Complete CI validation after the Actions run is approved.
- [ ] Move the completed task to `CHANGELOG.md`.

## Fix PHP 7.4 image build after PostgreSQL repository retirement

**Context:** [Build job 120090873865](https://github.com/drupalforge/deployment/actions/runs/39854997072/job/120090873865) fails because the inherited `bullseye-pgdg` APT repository no longer has a Release file. The deployment Dockerfile installs no APT packages.

**Status:** Fix implemented; full validation remains blocked locally.

**Done definition:**

- [x] Document why PECL installation does not refresh inherited APT repositories.
- [x] Add a regression test rejecting unnecessary APT refreshes while retaining extension and cache-cleanup checks.
- [x] Remove the unnecessary APT refresh; confirm the regression test fails before the fix and passes afterward, and the changed test passes ShellCheck.
- [ ] Complete unit, Docker build (including PHP 7.4), integration, and CI validation. Local builds cannot resolve PECL hosts; the unit suite passes 9 suites but fails on missing `markdownlint`/`phpcs` and existing ShellCheck diagnostics in unchanged files.

## Add Apache-only proxy exclusions env var and S3 asset ZIP import

### Documented plan only (no implementation in this task)

**Status:** Planning documented. Implementation intentionally deferred.

**Context:**
We need two deployment enhancements for Drupal Forge images:

- Add `FILE_PROXY_EXCLUDE_PATHS` to control Apache fallback rewrite exclusions for generated assets.
- Add `S3_ASSETS_ZIP_PATH` (plus optional related vars) to download and extract a required assets ZIP from S3.

Scope decision confirmed:

- `FILE_PROXY_EXCLUDE_PATHS` is Apache-only.
- Stage File Proxy will **not** consume or be configured by the new exclusion variable.
- Default Apache exclusion list should preserve current behavior: `/boost/,/css/,/js/,/styles/`.
- Asset ZIP extraction default should be `APP_ROOT`.

**Done definition:**

- [ ] `README.md` documents `FILE_PROXY_EXCLUDE_PATHS` as Apache-only and lists defaults/format.
- [ ] `README.md` documents `S3_ASSETS_ZIP_PATH` and optional `S3_ASSETS_BUCKET` + `S3_ASSETS_EXTRACT_ROOT`.
- [ ] `tests/test-setup-proxy.sh` adds coverage for env-driven Apache exclusions and default fallback behavior.
- [ ] New `tests/test-import-assets.sh` validates S3 ZIP URL construction, extraction, idempotency, and endpoint handling.
- [ ] New `scripts/import-assets.sh` is added and wired from `deployment-entrypoint.sh` after DB import and before proxy setup.
- [ ] `scripts/setup-proxy.sh` replaces hardcoded Apache exclusions with `FILE_PROXY_EXCLUDE_PATHS` while preserving defaults.
- [ ] Required verification commands pass locally:
  - `bash tests/test-setup-proxy.sh`
  - `bash tests/test-import-assets.sh`
  - `bash tests/unit-test.sh`
  - `bash tests/docker-build-test.sh`
  - `bash tests/integration-test.sh`
- [ ] Completed work is moved from `TODO.md` to `CHANGELOG.md` with date and summary.

**Planned implementation checklist:**

- [ ] Docs first: update `README.md` sections for file proxy and S3 asset ZIP import.
- [ ] Tests second: add/update unit + integration coverage for both features.
- [ ] Code last: implement `setup-proxy.sh`, `import-assets.sh`, and `deployment-entrypoint.sh` changes.

---

## Switch back to registry build cache

### Revert GHA cache to `type=registry` in `docker-publish-images.yml`

**File affected:**

- `.github/workflows/docker-publish-images.yml` (`cache-from` / `cache-to` in the "Build and push image" step)

**Background:**
The build cache was switched from `type=registry,mode=max` (Docker Hub) to `type=gha` (GitHub Actions cache) because of two open upstream BuildKit bugs that can cause `COPY` layers to serve stale data, meaning script updates could be silently omitted from published images:

- [moby/buildkit#4817](https://github.com/moby/buildkit/issues/4817) — `COPY` uses stale cached data when file content changes but metadata (filename, size, mtime) is unchanged.
- [moby/buildkit#2279](https://github.com/moby/buildkit/issues/2279) — registry `--cache-from` fails roughly 50% of the time in multi-platform builds.

**Action items:**

- [ ] Monitor moby/buildkit#4817 and moby/buildkit#2279 for fixes
- [ ] Once both issues are resolved, revert `cache-from` and `cache-to` in `.github/workflows/docker-publish-images.yml` back to `type=registry` and remove the `actions: write` permission from the `build` and `merge` jobs and the caller workflow

---
