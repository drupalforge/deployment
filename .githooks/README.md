# Git Hooks for Drupal Forge Deployment

This directory contains Git hooks to help maintain code quality by running tests before pushes.

## Available Hooks

### pre-push

The pre-push hook runs automatically before `git push` and performs the following:

1. **Detects changed files** since the last successful push
2. **Selectively runs tests** based on what changed:
   - If `Dockerfile` changed → Run Docker build + integration tests
   - If `scripts/` changed → Run unit + Docker build tests
   - If `tests/` changed → Run unit tests
   - If `.github/workflows/` changed → Run unit + Docker build tests
3. **Blocks the push** if any tests fail
4. **Cleans up** after tests automatically

When Git invokes hooks with stdin attached to a pipe instead of a terminal, the hook reattaches stdin to `/dev/tty` (when available). This allows test scripts to prompt for `sudo` credentials interactively instead of skipping sudo-dependent checks.

This ensures that:
- Only relevant tests run (faster feedback)
- Broken code doesn't get pushed
- Tests that passed before continue to pass

## Setup Instructions

### Quick Setup

Run this command from the repository root:

```bash
git config core.hooksPath .githooks
```

This tells Git to use the `.githooks` directory for all hooks.

### Verify Setup

Check that it's configured correctly:

```bash
git config core.hooksPath
# Should output: .githooks
```

### Manual Setup (Alternative)

If you prefer to keep using `.git/hooks`, you can create a symlink:

```bash
ln -sf ../../.githooks/pre-push .git/hooks/pre-push
```

## Testing the Hook

Try making a change and pushing:

```bash
# Make a small change
echo "# Test" >> README.md
git add README.md
git commit -m "Test commit"

# The hook will run before push
git push
```

You'll see output like:
```
╔════════════════════════════════════════════════════════════════╗
║                     Pre-Push Hook                              ║
╚════════════════════════════════════════════════════════════════╝

Tests to run:
  ✓ Unit tests

Running unit tests...
✓ Unit tests passed

╔════════════════════════════════════════════════════════════════╗
║         All tests passed! Proceeding with push...             ║
╚════════════════════════════════════════════════════════════════╝
```

## Bypassing the Hook

In emergencies, you can bypass the hook with:

```bash
git push --no-verify
```

**Warning:** Only use this when absolutely necessary, as it skips quality checks.

## Disabling the Hook

To temporarily disable:

```bash
# Revert to default hooks directory
git config --unset core.hooksPath
```

To re-enable:

```bash
git config core.hooksPath .githooks
```

## Hook Behavior

### What Gets Tested

The pre-push hook is smart about what to test:

| Changed Files | Tests Run |
|---------------|-----------|
| `Dockerfile` | Docker build + Integration |
| `scripts/*.sh` | Unit + Docker build |
| `tests/*.sh` | Unit tests |
| `.github/workflows/*` | Unit + Docker build |
| Other files | Unit tests (minimum) |

### Test Cleanup

All tests automatically clean up after themselves:
- Docker images created during tests are removed
- Test containers are stopped and removed
- Test volumes are deleted
- No leftover resources consume disk space

## Troubleshooting

### Hook not running

Check configuration:
```bash
git config core.hooksPath
```

Verify hook is executable:
```bash
ls -la .githooks/pre-push
# Should show -rwxr-xr-x (executable)
```

### Tests taking too long

The hook runs only relevant tests. If Docker build or integration tests are slow:
- Docker build tests: ~1-2 minutes
- Integration tests: ~3-5 minutes (only run for Dockerfile changes)

### Hook fails but tests pass locally

Make sure you're running the same tests:
```bash
cd tests
bash unit-test.sh           # Unit tests
bash docker-build-test.sh   # Docker builds
bash integration-test.sh    # Full integration
```

## Integration with CI

The pre-push hook complements CI rather than replacing it:

- **Pre-push hook**: Runs locally before push, tests only changed code
- **CI**: Runs on GitHub, tests everything on every PR

Both use the same test scripts for consistency.
