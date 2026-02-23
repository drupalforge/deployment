# Agent Guidelines for Drupal Forge Deployment

This file defines the standards and workflow that all agents (human or automated) must follow when contributing to this repository.

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
