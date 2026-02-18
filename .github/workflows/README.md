# GitHub Actions Workflows

This directory contains the CI/CD workflows for the Deployment Image repository.

## Workflows

### tests.yml

Runs unit tests and Docker builds for the deployment image.

#### Behavior

**On Push to Main:**
- Runs all tests automatically
- No approval required

**On Pull Request - Draft:**
- Workflow runs are created and require approval
- Jobs run after approval is granted
- Tests execute once approved

**On Pull Request - Ready for Review:**
- When marked ready, new workflow runs are triggered
- These new runs execute WITHOUT requiring approval
- Tests run automatically

**Concurrency:**
- Previous in-progress runs are automatically canceled when new runs start
- Only the most recent run for each PR is active

#### How Approval Works

GitHub's security policy requires approval for workflow runs from first-time contributors (like the Copilot bot). However:

1. **Draft PRs**: Workflow requires approval → jobs run after approval
2. **Marking PR ready**: Triggers `ready_for_review` event → new runs execute WITHOUT approval
3. **Concurrency setting**: Automatically cancels old runs, including those awaiting approval

This means draft PRs can be tested (after approval), while ready PRs run tests automatically without approval.

#### Concurrency Control

The workflow uses a concurrency setting to automatically cancel in-progress runs when a new run is triggered:
- `group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}`
- `cancel-in-progress: true`

This ensures that only the most recent workflow run for each PR or ref is active, preventing resource waste and reducing clutter.

#### Triggered Events

The workflow runs on:
- `push` to `main` branch
- `pull_request` events (default types: `opened`, `synchronize`, `reopened`)
  - No conditional logic - all jobs run for all PRs
  - Approval requirement is enforced by GitHub for first-time contributors
  - Ready-for-review PRs trigger new runs without approval

#### Jobs

1. **unit-tests**
   - Runs shell-based unit tests
   - Validates scripts and PHP syntax
   - Runs for all PRs (with approval for drafts)

2. **docker-build**
   - Builds Docker images for PHP 8.2 and 8.3
   - Validates Docker build process
   - Runs for all PRs (with approval for drafts)

2. **docker-build**
   - Builds Docker images for PHP 8.2 and 8.3
   - Validates Docker build process

### docker-publish-images.yml

Builds and publishes Docker images to Docker Hub when code is merged to main or tags are created.

### docker-publish-image.yml

Reusable workflow for building and publishing a single Docker image. Called by docker-publish-images.yml.
