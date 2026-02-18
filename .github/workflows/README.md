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

### auto-approve-copilot.yml

Automatically approves workflow runs from the Copilot bot to prevent manual approval requirements.

#### Why This Is Needed

GitHub treats the Copilot bot as a first-time/outside contributor, requiring manual approval before workflows can run on draft PRs. 

**Note:** When a draft PR is marked "ready for review," the `ready_for_review` event triggers new workflow runs that execute WITHOUT requiring approval. However, the old runs awaiting approval remain in that state and are not automatically canceled. This auto-approve workflow allows workflow runs to execute on draft PRs without waiting for manual approval or marking the PR ready.

#### How It Works

1. Triggers on `pull_request_target` events (opened, synchronize, reopened)
2. Checks if the actor is Copilot bot
3. Queries for workflow runs with `action_required` status
4. Automatically approves those runs using the GitHub API

**Important:** This workflow uses `pull_request_target`, which runs from the base branch (main), not from the PR branch. This ensures the workflow has the necessary permissions to approve other workflow runs.

#### Security Considerations

- Uses `pull_request_target` which has write permissions to approve workflows
- Only approves runs from Copilot bot specifically
- Requires `actions: write` permission to approve workflow runs

This is safer than disabling approval requirements for all outside contributors, as it maintains security while automating Copilot bot approvals.
