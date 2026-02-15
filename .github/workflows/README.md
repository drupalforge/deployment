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
- Uses `auto-approve` environment (no protection rules needed)
- **Automatically cancels any pending workflow runs** that were waiting for approval from when the PR was in draft state

**On Pull Request - Draft:**
- Requires manual approval before tests run
- Uses `draft-pr-approval` environment with required reviewers
- Tests run after approval is granted
- If the PR is later marked as ready for review, pending approval requests are automatically canceled

#### Setup Requirements

For draft PR approval to work, configure these environments in repository settings:

1. **draft-pr-approval** (with protection rules):
   - Go to Settings → Environments → New environment
   - Name: `draft-pr-approval`
   - Enable "Required reviewers"
   - Add team members who can approve test runs

2. **auto-approve** (no protection rules):
   - Go to Settings → Environments → New environment
   - Name: `auto-approve`
   - No protection rules needed

**Note:** The workflow will function without these environments, but approval requirements won't be enforced for draft PRs.

#### Triggered Events

The workflow runs on:
- `push` to `main` branch
- `pull_request` events: `opened`, `synchronize`, `reopened`, `ready_for_review`

#### Jobs

1. **cancel-pending-on-ready**
   - Cancels pending workflow runs waiting for approval when a PR becomes ready for review
   - Only runs when `ready_for_review` event is triggered
   - Uses workflow-specific API to only cancel runs from the same workflow file
   - Matches runs by head SHA for reliable PR identification
   - Ensures no stale approval requests remain when a draft PR transitions to ready

2. **approval-check**
   - Verifies PR status and applies appropriate environment
   - Only runs for pull request events
   - Outputs approval status for dependent jobs

3. **unit-tests**
   - Runs shell-based unit tests
   - Depends on approval-check for PRs
   - Validates scripts and PHP syntax

4. **docker-build**
   - Builds Docker images for PHP 8.2 and 8.3
   - Depends on approval-check for PRs
   - Validates Docker build process

### docker-publish-images.yml

Builds and publishes Docker images to Docker Hub when code is merged to main or tags are created.

### docker-publish-image.yml

Reusable workflow for building and publishing a single Docker image. Called by docker-publish-images.yml.
