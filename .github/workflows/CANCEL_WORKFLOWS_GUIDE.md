# Guide: Using cancel-workflows Action

## When NOT to Use cancel-workflows

The `viveklak/cancel-workflows` action should **NOT** be used in the tests workflow because:

1. **No manual approval steps**: The tests workflow doesn't have any environment protection rules requiring manual approval
2. **Concurrency already handles it**: GitHub's built-in `concurrency` with `cancel-in-progress: true` already cancels superseded workflow runs
3. **Wrong timing**: The action needs to run AFTER a successful deployment/approval, not before tests

## When TO Use cancel-workflows

Use this action in **deployment workflows** that have:

1. **Manual approval requirements**: Environment protection rules that require manual approval before deployment
2. **Multiple pending approvals**: Situations where multiple workflow runs can be stuck waiting for approval
3. **Trunk-based development**: Where you want to prevent accidentally approving and deploying an older version

## Proper Usage Example

For a deployment workflow with manual approval:

```yaml
name: Deploy

on:
  push:
    branches: [ main ]

permissions:
  contents: read
  actions: write  # Required for cancel-workflows-action

jobs:
  deploy-staging:
    runs-on: ubuntu-latest
    environment: staging  # No approval required
    steps:
      - uses: actions/checkout@v3
      - name: Deploy to staging
        run: ./deploy-staging.sh

  deploy-production:
    runs-on: ubuntu-latest
    needs: [deploy-staging]
    environment: production  # Requires manual approval
    steps:
      - uses: actions/checkout@v3
      - name: Deploy to production
        run: ./deploy-production.sh

  cancel-superseded-workflows:
    runs-on: ubuntu-latest
    # Run AFTER successful deployment
    if: ${{ always() && contains(join(needs.*.result, ','), 'success') }}
    needs: [deploy-production]
    steps:
      - uses: viveklak/cancel-workflows@v1.1.1
        with:
          # Cancels workflows waiting for approval that have been superseded by this run
          limit-to-previous-successful-run-commit: "true"
          # Set to false to actually cancel workflows (dry-run mode by default for safety)
          dry-run: "false"
```

## Key Points

1. **Position in workflow**: The cancel-superseded-workflows job should run **AFTER** the deployment job succeeds, not before
2. **Conditional execution**: Use `if: ${{ always() && contains(join(needs.*.result, ','), 'success') }}` to ensure it runs after deployment
3. **Required permissions**: The workflow needs `actions: write` permission
4. **Purpose**: To cancel older workflow runs that are still waiting for approval after a newer version has been deployed

## For Tests Workflow

For the tests workflow, the built-in concurrency control is sufficient:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: true
```

This automatically cancels in-progress runs when a new run is triggered, which is exactly what we need for tests.

## References

- [viveklak/cancel-workflows README](https://github.com/viveklak/cancel-workflows/blob/main/README.md)
- [GitHub Concurrency Documentation](https://docs.github.com/en/actions/using-jobs/using-concurrency)
- [GitHub Environment Protection Rules](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
