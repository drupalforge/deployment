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

The workflow uses a concurrency setting to automatically cancel in-progress runs when a new run is triggered:
- `group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}`
- `cancel-in-progress: true`

This ensures that only the most recent workflow run for each PR or ref is active, preventing resource waste and reducing clutter.

**Note**: The built-in concurrency cancellation does NOT cancel workflows that are waiting for environment approval. To handle these cases, the workflow includes a `cancel-superseded-workflows` job that uses the `viveklak/cancel-workflows` action to explicitly cancel approval-waiting workflows that have been superseded.

#### Jobs

1. **cancel-superseded-workflows**
   - Runs first to cancel any superseded workflows waiting for approval
   - Uses `viveklak/cancel-workflows` action
   - Required because built-in concurrency cancellation doesn't affect approval-waiting workflows
   - Configured with `dry-run: false` to actually perform cancellations

2. **unit-tests**
   - Runs shell-based unit tests
   - Validates scripts and PHP syntax
   - Depends on: `cancel-superseded-workflows`

3. **docker-build**
   - Builds Docker images for PHP 8.2 and 8.3
   - Validates Docker build process
   - Depends on: `cancel-superseded-workflows`

### docker-publish-images.yml

Builds and publishes Docker images to Docker Hub when code is merged to main or tags are created.

### docker-publish-image.yml

Reusable workflow for building and publishing a single Docker image. Called by docker-publish-images.yml.
