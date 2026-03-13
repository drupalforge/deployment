# TODO List

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
