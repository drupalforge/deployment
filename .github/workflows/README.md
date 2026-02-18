# GitHub Actions Workflows

This directory contains the CI/CD workflows for the Deployment Image repository.

## Workflows

### tests.yml

Runs unit tests and Docker builds for the deployment image.

#### Behavior

**On Push to Main:**
- Runs all tests automatically

**On Pull Request:**
- Workflow runs are created
- Tests execute on all PRs (draft and ready for review)

**Concurrency:**
- Previous in-progress runs are automatically canceled when new runs start
- Only the most recent run for each PR is active

#### Concurrency Control

The workflow uses a concurrency setting to automatically cancel in-progress runs when a new run is triggered:
- `group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}`
- `cancel-in-progress: true`

This ensures that only the most recent workflow run for each PR or ref is active, preventing resource waste and reducing clutter.

#### Triggered Events

The workflow runs on:
- `push` to `main` branch
- `pull_request` events: `opened`, `synchronize`, `reopened`, `ready_for_review`

#### Jobs

1. **unit-tests**
   - Runs shell-based unit tests
   - Validates scripts and PHP syntax

2. **docker-build**
   - Builds Docker images for PHP 8.2 and 8.3
   - Validates Docker build process

### docker-publish-images.yml

Builds and publishes Docker images to Docker Hub when code is merged to main or tags are created.

### docker-publish-image.yml

Reusable workflow for building and publishing a single Docker image. Called by docker-publish-images.yml.
