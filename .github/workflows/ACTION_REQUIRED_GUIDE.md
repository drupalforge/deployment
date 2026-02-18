# Understanding "action_required" Workflow Status

## What is "action_required"?

When a GitHub Actions workflow run shows `status: completed` and `conclusion: action_required`, it can mean one of two things:

### 1. Waiting for Manual Approval
The workflow contains a job that targets an environment with required reviewers or protection rules. The workflow is paused waiting for someone to approve or reject the deployment.

### 2. Canceled by Concurrency (Before Approval)
The workflow started and immediately reached an approval gate, but was then canceled by GitHub's concurrency mechanism (`cancel-in-progress: true`) when a newer run started. The workflow retains the `action_required` conclusion even though it was canceled.

## The Situation in This Repository

In the `drupalforge/deployment` repository, there are currently 5 workflow runs with `action_required` status for PR #18:

- Run #134 (created 2026-02-18T19:33:18Z)
- Run #135 (created 2026-02-18T19:35:07Z)
- Run #137 (created 2026-02-18T19:43:09Z)
- Run #138 (created 2026-02-18T19:43:46Z)
- Run #139 (created 2026-02-18T19:47:36Z)

### Key Observations

1. **No jobs executed**: All these runs have 0 jobs, meaning they were canceled before any work started
2. **Instant completion**: Created and updated timestamps are identical, indicating immediate cancellation
3. **No environment configured**: The `tests.yml` workflow has no `environment:` key in any job
4. **Concurrency is configured**: The workflow has `concurrency` with `cancel-in-progress: true`

### Conclusion

These runs were **canceled by the concurrency mechanism**, not actually waiting for approval. They show `action_required` because:
1. The workflow may have had a brief moment where it was queued
2. The concurrency mechanism canceled them before they could start
3. GitHub assigned them the `action_required` conclusion

## How to Handle action_required Runs

The Tests workflow now includes automatic cancellation logic that runs at the start of each PR workflow run. This job will:
- Cancel any previous Tests workflow runs for the same PR
- Only cancel runs that are `queued`, `in_progress`, or `waiting`
- Skip runs that have already completed

### What Happens Automatically

When a new commit is pushed to a PR:
1. A new Tests workflow run starts
2. The `cancel-previous-runs` job executes first
3. It finds and cancels any other Tests runs for the same PR
4. The `unit-tests` and `docker-build` jobs then proceed

### Manual Cancellation (If Needed)

If you need to manually cancel runs with `action_required` status:

#### Option 1: GitHub UI

1. Go to the Actions tab
2. Find each workflow run with "Action required" status
3. Click on the run
4. Click "Cancel workflow" button

#### Option 2: Using GitHub CLI

```bash
# List all action_required runs
gh run list --repo drupalforge/deployment --workflow=tests.yml --json conclusion,status,databaseId --jq '.[] | select(.conclusion=="action_required")'

# Cancel a specific run
gh run cancel RUN_ID --repo drupalforge/deployment
```

## Prevention

To prevent accumulation of `action_required` runs in the future:

### If You DON'T Need Approval Gates
The current setup is correct:
- Use `concurrency` with `cancel-in-progress: true`  
- Do NOT add environment protection rules to test workflows
- Canceled runs will show as `action_required` but have 0 jobs

### If You DO Need Approval Gates
Use the `viveklak/cancel-workflows` action:
1. Add it as a job that runs AFTER successful deployment
2. Configure it to cancel superseded approval-waiting runs
3. See `.github/workflows/CANCEL_WORKFLOWS_GUIDE.md` for examples

## Technical Details

### Why 0 Jobs?
When a workflow is canceled by concurrency before any jobs start:
- No jobs are created
- The run status is `completed`
- The conclusion may be `action_required` or `cancelled`
- The run appears in the workflow history but did no work

### Why action_required Instead of cancelled?
GitHub's concurrency mechanism assigns different conclusions based on the workflow state when cancellation occurs:
- If canceled while queued or starting: `action_required`
- If canceled while running: `cancelled`
- The exact behavior can vary based on timing

## References

- [GitHub Concurrency Documentation](https://docs.github.com/en/actions/using-jobs/using-concurrency)
- [GitHub Deployments and Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
- [Cancel Workflows Action Guide](.github/workflows/CANCEL_WORKFLOWS_GUIDE.md)
