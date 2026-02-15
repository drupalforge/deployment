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
- Tests are skipped (workflow does not run)
- Mark PR as "ready for review" to run tests

This follows the standard GitHub Actions pattern for handling draft PRs.

#### Triggered Events

The workflow runs on:
- `push` to `main` branch
- `pull_request` events: `opened`, `synchronize`, `reopened`, `ready_for_review`
  - Skips draft PRs using `if: !github.event.pull_request.draft`

#### Jobs

1. **unit-tests**
   - Runs shell-based unit tests
   - Skips draft PRs
   - Validates scripts and PHP syntax

2. **docker-build**
   - Builds Docker images for PHP 8.2 and 8.3
   - Skips draft PRs
   - Validates Docker build process

### docker-publish-images.yml

Builds and publishes Docker images to Docker Hub when code is merged to main or tags are created.

### docker-publish-image.yml

Reusable workflow for building and publishing a single Docker image. Called by docker-publish-images.yml.
