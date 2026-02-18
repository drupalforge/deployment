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
- Cancels any previous workflow runs that were awaiting approval

**On Pull Request - Draft:**
- Workflow runs are created but require manual approval
- Approval requirement prevents automatic execution
- Mark PR as "ready for review" to run tests without approval and cancel pending runs

This approach relies on GitHub's approval requirement for first-time contributors instead of using conditional logic to skip draft PRs.

#### Triggered Events

The workflow runs on:
- `push` to `main` branch
- `pull_request` events: `opened`, `synchronize`, `reopened`, `ready_for_review`
  - All events trigger workflow runs
  - Draft PRs require approval (enforced by GitHub repository settings)
  - Ready PRs run without approval and cancel previous awaiting runs

#### Jobs

1. **cancel-previous**
   - Only runs when PR is marked "ready for review"
   - Cancels workflow runs awaiting approval
   - Prevents stale pending runs from cluttering the UI

2. **unit-tests**
   - Runs shell-based unit tests
   - Depends on cancel-previous (runs even if cancel-previous is skipped)
   - Validates scripts and PHP syntax

3. **docker-build**
   - Builds Docker images for PHP 8.2 and 8.3
   - Depends on cancel-previous (runs even if cancel-previous is skipped)
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
