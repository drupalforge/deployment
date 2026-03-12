# TODO List

## Fix integration test failures (apache-start.sh template overwrite)

### Ensure proxy rules survive apache-start.sh template copy before Apache starts

**Context:**
`deployment-entrypoint.sh` calls `setup-proxy.sh` which injects rewrite rules into
`/etc/apache2/sites-enabled/000-default.conf`. However, `apache-start.sh` (the DevPanel
base image startup script) runs `sudo cp /templates/000-default.conf /etc/apache2/sites-enabled/000-default.conf`
AFTER the entrypoint finishes, overwriting the injected rules. Apache then starts with no proxy rules,
causing integration tests 1 (rewrite rules grep), 2 (file download), 3 (file on disk), and 4
(secure-mode download) to fail.

**Done definition:**
- [x] `scripts/apache2-foreground-wrapper.sh` created — runs `setup-proxy.sh` after template substitution, then calls `exec apache2 -DFOREGROUND`
- [x] `Dockerfile` COPY replaces `/usr/local/bin/apache2-foreground` with wrapper
- [x] `bash tests/test-setup-proxy.sh` passes locally
- [x] `bash tests/unit-test.sh` passes locally
- [ ] CI integration tests pass

**Action items:**
- [x] Create wrapper script
- [x] Update Dockerfile
- [x] Run unit tests
- [ ] Verify CI

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


