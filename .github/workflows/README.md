# GitHub Actions Workflows

This directory contains the CI/CD workflows for the Deployment Image repository.

## Workflows

### tests.yml

Runs unit tests and Docker builds for the deployment image.

#### Triggered Events

The workflow runs on:

- `push` to `main` branch
- `pull_request` events: `opened`, `synchronize`, `reopened`, `ready_for_review`

#### Concurrency Control

The workflow uses multiple mechanisms to ensure only the most recent run is active:

1. **Built-in concurrency setting**: Cancels in-progress runs when a new run starts
   - `group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}`
   - `cancel-in-progress: true`

2. **Explicit cancellation job**: The `cancel-previous-runs` job runs at the start of each PR workflow to cancel any previous runs for the same PR, including those that are `queued`, `in_progress`, `waiting`, or completed with `action_required` status.

This ensures that only the most recent workflow run for each PR or ref is active, preventing resource waste and reducing clutter.

#### Jobs

1. **cancel-previous-runs** (PR workflows only)
   - Runs first to cancel previous workflow runs for the same PR
   - Uses GitHub API to find and cancel all matching runs regardless of status
   - Skips if the workflow is triggered by a push to main (not a PR)

2. **unit-tests**
   - Runs shell-based unit tests
   - Validates scripts and PHP syntax
   - Depends on: `cancel-previous-runs`

3. **docker-build**
   - Builds Docker images for PHP 8.2 and 8.3
   - Validates Docker build process
   - Depends on: `cancel-previous-runs`

### docker-publish-images.yml

Builds and publishes Docker images to Docker Hub. Triggered on successful completion of the Tests workflow on `main`, on tag pushes (`v*.*.*`), or manually via `workflow_dispatch`.

Uses a matrix strategy to build images for each PHP version (`8.2`, `8.3`) and each platform (`linux/amd64`, `linux/arm64`) in parallel. Per-platform digests are uploaded as artifacts and combined into a tagged multi-arch manifest list by a final `merge` job.

Tags produced:
- `{version}-php-{phpversion}` on semver tag pushes (e.g. `1.2.3-php-8.3`)
- `php-{phpversion}` on the default branch (e.g. `php-8.3`)
- `{branch}-php-{phpversion}` on non-default branches
