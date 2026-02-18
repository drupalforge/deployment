# GitHub Actions Workflows

This directory contains the CI/CD workflows for the Deployment Image repository.

## Workflows

### tests.yml

Runs unit tests and Docker builds for the deployment image.

#### Behavior

**On Push to Main:**
- Runs all tests automatically
- No approval required

**On Pull Request - Ready for Review:**
- Runs all tests automatically
- No approval required
- Cancels any previous in-progress workflow runs

**On Pull Request - Draft:**
- Workflow runs are created but jobs are skipped
- Tests do not run on draft PRs
- Mark PR as "ready for review" to run tests

This approach uses conditional logic (`if: !github.event.pull_request.draft`) to skip jobs for draft PRs, ensuring that only ready-for-review PRs execute tests.

#### Concurrency Control

The workflow uses a concurrency setting to automatically cancel in-progress runs when a new run is triggered:
- `group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}`
- `cancel-in-progress: true`

This ensures that only the most recent workflow run for each PR or ref is active, preventing resource waste and reducing clutter.

#### Triggered Events

The workflow runs on:
- `push` to `main` branch
- `pull_request` events (default types: `opened`, `synchronize`, `reopened`)
  - Jobs are skipped for draft PRs using `if: !github.event.pull_request.draft`
  - Ready-for-review PRs run without requiring approval
  - Previous runs are automatically canceled when new runs start (via concurrency setting)

#### Jobs

1. **unit-tests**
   - Runs shell-based unit tests
   - Skips draft PRs (via `if` condition)
   - Validates scripts and PHP syntax

2. **docker-build**
   - Builds Docker images for PHP 8.2 and 8.3
   - Skips draft PRs (via `if` condition)
   - Validates Docker build process

2. **docker-build**
   - Builds Docker images for PHP 8.2 and 8.3
   - Validates Docker build process

### docker-publish-images.yml

Builds and publishes Docker images to Docker Hub when code is merged to main or tags are created.

### docker-publish-image.yml

Reusable workflow for building and publishing a single Docker image. Called by docker-publish-images.yml.
