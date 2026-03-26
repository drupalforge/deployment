# TODO List

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
- [ ] Once both issues are resolved, revert `cache-from` and `cache-to` in `.github/workflows/docker-publish-images.yml` back to `type=registry` and remove the `actions: write` permission from the `build-and-push` job and the caller workflow

---
