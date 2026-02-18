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

**On Pull Request - Draft:**
- Workflow runs but skips test jobs (shows as successful)
- Mark PR as "ready for review" to run tests

This uses a conditional check job pattern to avoid "action_required" status on draft PRs.

#### Triggered Events

The workflow runs on:
- `push` to `main` branch
- `pull_request` events: `opened`, `synchronize`, `reopened`, `ready_for_review`
  - Skips test jobs for draft PRs using conditional check job pattern

#### Jobs

1. **check-if-should-run**
   - Always runs and succeeds
   - Determines if test jobs should run based on draft status
   - Prevents "action_required" status on draft PRs

2. **unit-tests**
   - Depends on check-if-should-run
   - Runs shell-based unit tests
   - Skips for draft PRs
   - Validates scripts and PHP syntax

3. **docker-build**
   - Depends on check-if-should-run
   - Builds Docker images for PHP 8.2 and 8.3
   - Skips for draft PRs
   - Validates Docker build process

### docker-publish-images.yml

Builds and publishes Docker images to Docker Hub when code is merged to main or tags are created.

### docker-publish-image.yml

Reusable workflow for building and publishing a single Docker image. Called by docker-publish-images.yml.
