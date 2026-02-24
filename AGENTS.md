# Agent Guidelines for Drupal Forge Deployment

This file defines the standards and workflow that all agents (human or automated) must follow when contributing to this repository.

## Deployment Context

Images built from this repository are deployed by **DevPanel** to run Drupal sites on [Drupal Forge](https://www.drupalforge.org/). Agents must keep this in mind when making any change:

- **DevPanel deploys the image** — the container is started by DevPanel, not by a human operator running `docker run`. Any behaviour that relies on flags or environment variables being passed manually will not work in production.
- **DevPanel provides environment variables automatically** — `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, and `DB_NAME` are injected by DevPanel at runtime. Do not hardcode or require these to be set manually.
- **DevPanel handles source code** — it clones the repository and checks out the correct branch before the container starts. The deployment image only needs to handle post-clone steps (Git submodule init, Composer install, etc.).
- **Changes to the entrypoint or startup sequence must remain compatible** with DevPanel's expectations. Do not rename, move, or remove the deployment entrypoint (`deployment-entrypoint.sh`) or change its exit behaviour without understanding the impact on DevPanel's orchestration.
- **Do not introduce host-level dependencies** — the image must be fully self-contained. DevPanel does not guarantee any specific host tooling beyond what is standard in the base image.

## Workflow Order

1. **Document first** — before writing any code or tests, update or create the relevant documentation (README, inline comments, environment variable tables). This ensures the intended behavior is understood and agreed upon before implementation begins.
2. **Write tests second** — add or update unit and/or integration tests that will fail until the implementation is complete.
3. **Write code last** — implement the change to make the failing tests pass.

Every change that touches executable code **must** have a corresponding test.

## Defining Done

Before starting any task, write a short "done" definition in `TODO.md` so work has a clear end-point and does not continue indefinitely. A task is done when:

- All items in the done definition are satisfied.
- All relevant tests pass locally **and** in CI.
- Documentation has been updated and cleaned up.
- `TODO.md` has been updated to reflect completion.

## Tests Must Pass Locally and in CI

- Run the full unit test suite locally before pushing:
  ```bash
  bash tests/unit-test.sh
  ```
- For changes to `Dockerfile`, `scripts/`, or `.github/workflows/`, also run the Docker build test:
  ```bash
  bash tests/docker-build-test.sh
  ```
- The repository provides a pre-push Git hook that runs the relevant tests automatically. Enable it with:
  ```bash
  git config core.hooksPath .githooks
  ```
- Do **not** push code that fails any test, even with `--no-verify`, unless explicitly directed by a human maintainer.
- CI (GitHub Actions `tests.yml`) must also pass before a pull request is merged.

## Tests Must Clean Up After Themselves

Every test script is responsible for removing any resources it creates:

- Temporary files and directories created under `/tmp` must be deleted in a `trap` or cleanup block.
- Docker containers, images, networks, and volumes created during tests must be removed when the test exits (pass or fail).
- No leftover state should affect subsequent test runs or the host environment.

Example pattern for shell-based tests:
```bash
TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT
```

**Fixture note:** Integration tests create a temporary `tests/fixtures/app/.gitignore` to ignore generated fixture files. Do not add a permanent `.gitignore` in that directory or move generated files outside the repo to avoid dirty status.

## Plans and Progress in TODO.md

- Track ongoing work, open questions, and deferred improvements in `TODO.md` at the repository root.
- Each item should include: context, action items as a checklist, and references.
- Mark items complete (`[x]`) or remove them when they are resolved.
- Do not track ephemeral in-flight notes anywhere else in the repository.

## Clean Up Documentation When Done

When a task is finished:

- Remove or update any temporary notes, placeholder text, or stale documentation.
- Ensure `README.md` accurately reflects the current behavior.
- Ensure `TODO.md` no longer lists items that are already resolved.
- Remove any documentation that was written specifically for the work-in-progress state.

## Test Output Formatting

Every test script must produce output using the following conventions so that the runner (`tests/unit-test.sh`) and humans can parse results consistently.

| Situation | Format |
|-----------|--------|
| Suite header (first line) | `echo -e "${BLUE}Testing <component>...${NC}"` |
| Passing assertion | `echo -e "${GREEN}✓ <description>${NC}"` |
| Failing assertion | `echo -e "${RED}✗ <description>${NC}"` then `exit 1` |
| Skipped / optional assertion | `echo -e "${YELLOW}⊘ <description>${NC}"` |
| Suite summary (last line) | `echo -e "${GREEN}✓ <Suite name> tests passed${NC}"` |

Rules:
- `${GREEN}` is reserved for assertions that passed.
- `${RED}` is reserved for assertions that failed; always exit with a non-zero status immediately after.
- `${YELLOW}` is reserved for skipped or optional assertions (ones that do not fail the suite). Do **not** use `${YELLOW}` for general informational or progress messages.
- `${BLUE}` is used for structural output: the suite header and any other non-result informational messages (e.g., `echo -e "${BLUE}  Linting $n files...${NC}"`).
- Each test script must define the color variables (`RED`, `GREEN`, `YELLOW`, `BLUE`, `NC`) locally; do not assume they are inherited from the environment.
- If a test directly invokes sourced/evaluated script functions, capture stdout/stderr and only print that output when the assertion fails. Passing output must remain assertion-formatted only.

## Tests Requiring Sudo

Tests that require elevated privileges (for operations like changing file ownership, modifying read-only files, or running destructive operations) must use the `setup_sudo()` library function for credential probing and management.

### When a Test Requires Sudo

A test needs sudo when it:
- Creates or modifies read-only files or directories
- Changes file or directory ownership
- Performs cleanup operations that require elevation
- Simulates permission errors or cross-user scenarios

Examples: `tests/test-bootstrap-app.sh` (test 10 for read-only settings append), `tests/test-deployment-entrypoint.sh` (permission modification tests).

### Using the Sudo Setup Library

**All test scripts requiring sudo must use the `tests/lib/sudo.sh` library.** Do not reimplement sudo credential management in individual test files.

Setup is simple — just source the library (which internally sources `lib/utils.sh`):

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR=$(mktemp -d)

# shellcheck source=lib/sudo.sh
source "$TEST_DIR/lib/sudo.sh"

# Setup sudo credentials, background refresh, and cleanup trap
setup_sudo "$TEMP_DIR"

# Check current non-interactive sudo availability via library helper
if ! ensure_active_sudo; then
  echo -e "${YELLOW}⊘ Skipped: test requires sudo${NC}"
  return 0
fi
```

### Library Function Reference

**`setup_sudo [temp_dir]`**

Initializes sudo credentials and manages the complete lifecycle:
- Resets inherited sudo state at the start of each call (fresh process-local probe)
- Probes for sudo availability (via `sudo -n` for cached credentials or interactive `sudo -v` if needed)
- Exports `SUDO_AVAILABLE` (1 if credentials available, 0 otherwise)
- Exports `SUDO_PROBED` (internal compatibility flag; tests should not set or depend on it)
- Starts a background process to refresh credentials every 30 seconds
- Exports `SUDO_REFRESH_PID` for reference (library manages cleanup automatically)
- Optionally sets up cleanup trap if `temp_dir` is provided

**`ensure_active_sudo`**

Checks whether non-interactive sudo is currently available in the calling process.
- Returns success (0) when `sudo -n` works
- Returns failure (1) when credentials are not active
- Updates `SUDO_AVAILABLE` to match runtime state

**Arguments:**
- `temp_dir` (optional): Directory to remove on exit with elevated privileges if needed

**Exports:**
- `SUDO_AVAILABLE`: 1 if sudo credentials available, 0 otherwise
- `SUDO_PROBED`: internal compatibility flag
- `SUDO_REFRESH_PID`: PID of background refresh process (if active)

### Using Sudo Credentials in Tests

Once `setup_sudo` has been called, check credentials before attempting privileged operations:

```bash
# Skip the test if sudo is required but not currently active
if ! ensure_active_sudo; then
  echo -e "${YELLOW}⊘ Skipped: read-only settings append test requires sudo${NC}"
  return 0
fi

# Use sudo -n (non-interactive) for operations that require elevation
sudo -n chmod 644 "${settings_file}"
```

**Key points:**
- Call `setup_sudo` once per test script near the top; do not manually unset/reset `SUDO_*` variables in test files.
- Use `ensure_active_sudo` from `tests/lib/sudo.sh` instead of custom per-test probe helpers.
- Always use `sudo -n` (non-interactive) in tests; credentials were already verified during setup.
- Use skipped assertions (`${YELLOW}⊘`) for optional tests that cannot proceed without sudo, not failed assertions (`${RED}✗`).
- Skipped messages must start with `Skipped:` and include the test name so output clearly identifies what was skipped.
- The library trap handles all cleanup automatically — no need to write custom cleanup functions.

### Ordering Sudo-Dependent Tests

To reduce credential-expiration risk and avoid unnecessary re-prompts:

- Place **all sudo-dependent test calls first** in each test file's "Run tests" section.
- Order sudo-dependent tests by **expected runtime, shortest to longest**.
- Run non-sudo tests after all sudo-dependent tests.

Examples:
- In `tests/test-bootstrap-app.sh`, keep sudo-required checks grouped at the top of the run list.
- In `tests/test-deployment-entrypoint.sh`, run ownership/permission sudo tests before non-sudo timing and grep-based checks.

### Troubleshooting Sudo Credential Expiration

If sudo-dependent tests are unexpectedly skipped or intermittently fail in longer runs:

- Re-authenticate before running tests:
  ```bash
  sudo -v
  bash tests/unit-test.sh
  ```
- Verify non-interactive sudo is active in the current shell:
  ```bash
  sudo -n true && echo "sudo active"
  ```
- If `sudo -n true` fails, rerun with an interactive terminal and complete the password prompt.
- Ensure sudo-dependent tests remain ordered first (shortest to longest) so privileged checks execute before credentials age.

### How the Library Works

The `setup_sudo()` function implements a complete sudo management solution:

1. **Credential Probing**: Checks if sudo is available non-interactively first, then uses interactive countdown prompt if needed
2. **Countdown Timer**: When TTY is available, displays "30 sec remaining" with live countdown for user convenience
3. **State Reset + Fresh Probe**: Clears inherited `SUDO_*` state and re-probes in the current process
4. **Background Refresh**: Starts a background process that refreshes credentials every 30 seconds during test execution
5. **Automatic Cleanup**: Sets up a trap to kill the refresh process and clean up the temp directory on exit
6. **Parallel-Safe**: Works correctly when multiple test suites run in parallel; each gets fresh credentials from the shared background refresh loop

The countdown is only displayed when:
- No cached sudo credentials are available (`sudo -n` fails)
- Both stdin AND stdout are connected to a TTY (interactive session)
- Not in a CI environment

### Example Implementations

Reference implementations showing clean, minimal sudo usage:
- **`tests/test-deployment-entrypoint.sh`**: Primary example with multiple sudo-requiring tests and proper skip patterns
- **`tests/test-bootstrap-app.sh`**: Additional test file example
- **`tests/unit-test.sh`**: Master test runner calling `setup_sudo` (all probing and countdown handled by library)
- **`tests/lib/sudo.sh`**: The library implementation (do not modify — report issues instead)

### Do Not Reimplement

Developers should **never** manually implement sudo probing or refresh logic in test files. If you need to:
- Modify how credentials are probed or managed
- Change refresh intervals  
- Change how active-credential checks are performed in tests
- Add new credential management features

Then update `tests/lib/sudo.sh` instead, and all tests will automatically benefit from the improvement.


## Test Coverage Requirements

Tests must cover all of the following dimensions:

### Security
- Validate that secrets and credentials are never logged or written to disk.
- Confirm that scripts reject invalid or missing required environment variables rather than proceeding silently.
- Verify that file permissions follow the principle of least privilege.

### Coding Standards
- Shell scripts must pass `shellcheck` (or equivalent linter) with no errors.
- PHP files must follow PSR-12 (validated by the existing test suite via `test-proxy-handler.sh`).
- YAML files must pass `yamllint` (validated by `tests/test-yaml-lint.sh`).
- Dockerfile must follow the conventions checked by `tests/test-dockerfile.sh`.

### Functionality — Individual Components
- Each script in `scripts/` must have a corresponding `tests/test-<script-name>.sh` unit test file.
- Unit tests must cover both success paths and expected failure paths.
- External dependencies (AWS S3, MySQL, HTTP origins) must be mocked in unit tests.

### Functionality — Whole Project
- Integration tests (`tests/integration-test.sh`) must validate the complete startup flow end-to-end:
  - Database import from S3 (mocked with MinIO locally).
  - File proxy setup and on-demand download.
  - Bootstrap (Git submodules + Composer).
- Run integration tests before finalizing any change that touches the `Dockerfile`, `scripts/`, or `config/`.

## Quick Reference

| Task | Command |
|------|---------|
| Run all unit tests | `bash tests/unit-test.sh` |
| Run a single unit test | `bash tests/test-<component>.sh` |
| Run Docker build test | `bash tests/docker-build-test.sh` |
| Run integration tests | `bash tests/integration-test.sh` |
| Run all tests | `bash tests/run-all-tests.sh` |
| Enable pre-push hook | `git config core.hooksPath .githooks` |
