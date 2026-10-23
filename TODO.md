# TODO List

## Switch integration tests from S3Mock to RustFS

**Context:** [Integration job 120113548672](https://github.com/drupalforge/deployment/actions/runs/39860508216/job/120113548672) could not pull the retired `minio/minio` and `minio/mc` images. The first replacement used Adobe S3Mock; RustFS is preferred as a community-maintained S3-compatible storage server. Do not pin the RustFS image tag.

**Status:** Fixed the setup command parsing bug exposed by CI job [120495821066](https://github.com/drupalforge/deployment/actions/runs/39976955022/job/120495821066): Compose split the multiline command, so Bash executed only `set` and exited successfully without uploading the fixture. The script is now one argument, with a passing rendered-command regression test covering success and readiness/create/upload failures. YAML lint passes. Full integration validation remains blocked by PECL DNS resolution during the image build; the unit suite passes 9 suites and fails 3 on missing `markdownlint`/`phpcs` and existing ShellCheck findings in unchanged files. CI validation is pending.

**Done definition:**

- [x] Document RustFS as the integration S3 backend.
- [x] Update regression checks and Compose to run RustFS without pinning the image tag.
- [x] Verify AWS CLI bucket creation and database fixture upload/download against RustFS.
- [x] Add a regression test executing the rendered setup command with mocked AWS CLI success and failure paths.
- [x] Preserve the complete setup script as one Bash command argument.
- [x] Run focused tests; attempt full integration and unit suites, and record environment limitations.
- [ ] Complete CI validation and move this task to `CHANGELOG.md`.

## Repair inherited PostgreSQL APT source for Debian Bullseye

**Context:** [Build job 120090873865](https://github.com/drupalforge/deployment/actions/runs/39854997072/job/120090873865) fails because the inherited `bullseye-pgdg` APT repository no longer has a Release file. The deployment Dockerfile installs no APT packages.

**Status:** In progress. The initial fix removed the unnecessary APT refresh but did not repair the inherited source, as called out in PR feedback.

**Done definition:**

- [x] Confirm the inherited PHP 7.4 image uses active Debian mirrors and a separate PGDG `bullseye-pgdg` source.
- [ ] Migrate only the retired Bullseye PGDG source to `apt-archive.postgresql.org` / `bullseye-pgdg-archive`, then run `apt-get update`.
- [ ] Replace the regression test that forbids APT refresh with checks for the source migration and refresh.
- [ ] Validate the PHP 7.4 build and relevant tests; record any remaining network limitations.

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
