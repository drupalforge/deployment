#!/bin/bash
set -e

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$TEST_DIR/docker-compose.test.yml"
MANUAL_COMPOSE_FILE="$TEST_DIR/docker-compose.manual.yml"
GITIGNORE_FILE="$TEST_DIR/../.gitignore"
INTEGRATION_SCRIPT="$TEST_DIR/integration-test.sh"
SHARED_ENV_FILE="$TEST_DIR/.env.shared"
TEST_ENV_FILE="$TEST_DIR/.env.test"
CLEANUP_SCRIPT="$TEST_DIR/cleanup-test-environment.sh"

# shellcheck source=lib/colors.sh
source "$TEST_DIR/lib/colors.sh"

echo -e "${BLUE}Testing integration compose startup...${NC}"

if grep -q "app-fixture-init:" "$COMPOSE_FILE"; then
    echo -e "${RED}✗ Compose file still defines legacy app-fixture-init service${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Legacy app-fixture-init service removed${NC}"
fi

if grep -q "app-fixture-setup:" "$COMPOSE_FILE"; then
    echo -e "${RED}✗ Compose file still defines legacy app-fixture-setup service${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Legacy app-fixture-setup service removed${NC}"
fi

if grep -q "app-fixture-prepare:" "$COMPOSE_FILE"; then
    echo -e "${GREEN}✓ Compose file defines app-fixture-prepare service${NC}"
else
    echo -e "${RED}✗ Compose file is missing app-fixture-prepare service${NC}"
    exit 1
fi

if grep -A20 "deployment:" "$COMPOSE_FILE" | grep -q "app-fixture-prepare:"; then
    echo -e "${GREEN}✓ Deployment depends on fixture prepare service${NC}"
else
    echo -e "${RED}✗ Deployment does not depend on fixture prepare service${NC}"
    exit 1
fi

if grep -q "condition: service_completed_successfully" "$COMPOSE_FILE"; then
    echo -e "${GREEN}✓ Fixture prepare uses one-shot completion dependency${NC}"
else
    echo -e "${RED}✗ Compose file is missing service_completed_successfully dependency${NC}"
    exit 1
fi

if grep -q "chown -R www:www /var/www/html" "$COMPOSE_FILE"; then
    echo -e "${GREEN}✓ Fixture prepare repairs bind-mount ownership${NC}"
else
    echo -e "${RED}✗ Compose file is missing fixture ownership repair${NC}"
    exit 1
fi

if grep -A30 "app-fixture-prepare:" "$COMPOSE_FILE" | grep -q "^[[:space:]]*env_file:" &&
   grep -q "^[[:space:]]*-[[:space:]]*\.env\.shared$" "$COMPOSE_FILE" &&
   grep -q "^[[:space:]]*-[[:space:]]*\.env\.test$" "$COMPOSE_FILE" &&
   grep -q "case \"\$\$DP_REPO_BRANCH\" in" "$COMPOSE_FILE"; then
    echo -e "${GREEN}✓ Fixture init reads DP_REPO_BRANCH from shared/test env files${NC}"
else
    echo -e "${RED}✗ app-fixture-prepare must load .env.shared + .env.test and read DP_REPO_BRANCH in entrypoint${NC}"
    exit 1
fi

if grep -q "repo_url=\"\$\${DP_REPO_BRANCH%%/-/tree/\*}\.git\"" "$COMPOSE_FILE" &&
   grep -q "repo_branch=\"\$\${DP_REPO_BRANCH##\*/-/tree/}\"" "$COMPOSE_FILE" &&
   grep -q "repo_url=\"\$\${DP_REPO_BRANCH%%/tree/\*}\.git\"" "$COMPOSE_FILE" &&
   grep -q "repo_branch=\"\$\${DP_REPO_BRANCH##\*/tree/}\"" "$COMPOSE_FILE" &&
   grep -q "git clone --branch \"\$\$repo_branch\" --single-branch --depth 1" "$COMPOSE_FILE"; then
    echo -e "${GREEN}✓ Fixture init derives clone URL and branch from GitHub/GitLab DP_REPO_BRANCH formats${NC}"
else
    echo -e "${RED}✗ Compose file must derive clone URL/branch from GitHub and GitLab DP_REPO_BRANCH formats before git clone${NC}"
    exit 1
fi

if grep -A40 "deployment:" "$COMPOSE_FILE" | grep -q "^[[:space:]]*env_file:" &&
   grep -q "^[[:space:]]*-[[:space:]]*\.env\.shared$" "$COMPOSE_FILE" &&
   grep -q "^[[:space:]]*-[[:space:]]*\.env\.test$" "$COMPOSE_FILE"; then
    echo -e "${GREEN}✓ Deployment service loads .env.shared + .env.test${NC}"
else
    echo -e "${RED}✗ Deployment service must load .env.shared + .env.test${NC}"
    exit 1
fi

if [ -f "$SHARED_ENV_FILE" ] &&
   grep -q "^DP_REPO_BRANCH=https://github.com/drupal/recommended-project/tree/11.x$" "$SHARED_ENV_FILE" &&
   grep -q "^DB_HOST=mysql$" "$SHARED_ENV_FILE" &&
   grep -q "^S3_DATABASE_PATH=test-db.sql.gz$" "$SHARED_ENV_FILE" &&
   ! grep -q "^AWS_S3_ENDPOINT=" "$SHARED_ENV_FILE"; then
    echo -e "${GREEN}✓ .env.shared defines shared defaults and omits AWS_S3_ENDPOINT${NC}"
else
    echo -e "${RED}✗ .env.shared must include shared defaults and omit AWS_S3_ENDPOINT${NC}"
    exit 1
fi

if [ -f "$TEST_ENV_FILE" ] &&
   grep -q "^AWS_S3_ENDPOINT=http://minio:9000$" "$TEST_ENV_FILE"; then
    echo -e "${GREEN}✓ .env.test defines test-only AWS_S3_ENDPOINT default${NC}"
else
    echo -e "${RED}✗ .env.test must exist and define AWS_S3_ENDPOINT default${NC}"
    exit 1
fi

if grep -q "git clone --branch 11.x" "$INTEGRATION_SCRIPT"; then
    echo -e "${RED}✗ integration-test.sh still performs host-side fixture cloning${NC}"
    exit 1
else
    echo -e "${GREEN}✓ integration-test.sh does not perform host-side fixture cloning${NC}"
fi

if grep -q "composer require drush/drush drupal/stage_file_proxy" "$INTEGRATION_SCRIPT"; then
    echo -e "${RED}✗ integration-test.sh still performs host-side fixture composer install${NC}"
    exit 1
else
    echo -e "${GREEN}✓ integration-test.sh does not perform host-side fixture composer install${NC}"
fi

if [ -f "$CLEANUP_SCRIPT" ] && [ -x "$CLEANUP_SCRIPT" ]; then
    echo -e "${GREEN}✓ Shared cleanup script exists and is executable${NC}"
else
    echo -e "${RED}✗ tests/cleanup-test-environment.sh must exist and be executable${NC}"
    exit 1
fi

if grep -q "CLEANUP_SCRIPT=\"\$SCRIPT_DIR/cleanup-test-environment.sh\"" "$INTEGRATION_SCRIPT" &&
   grep -q "bash \"\$CLEANUP_SCRIPT\" --mode stale" "$INTEGRATION_SCRIPT" &&
   grep -q "bash \"\$CLEANUP_SCRIPT\" --mode full" "$INTEGRATION_SCRIPT"; then
    echo -e "${GREEN}✓ integration-test.sh uses shared cleanup script for stale/full cleanup${NC}"
else
    echo -e "${RED}✗ integration-test.sh must use shared cleanup script for stale/full cleanup${NC}"
    exit 1
fi

if grep -q "SECURE_PRIVATE_CONTAINER_NAME=\"\${TEST_COMPOSE_PROJECT}-secure-private-once\"" "$INTEGRATION_SCRIPT" &&
   grep -q "NOIMPORT_CONTAINER_NAME=\"\${TEST_COMPOSE_PROJECT}-noimport-once\"" "$INTEGRATION_SCRIPT"; then
    echo -e "${GREEN}✓ integration-test.sh defines stable names for one-off validation containers${NC}"
else
    echo -e "${RED}✗ integration-test.sh must define stable names for secure/no-import validation containers${NC}"
    exit 1
fi

if grep -A40 "deployment:" "$COMPOSE_FILE" | grep -q "^[[:space:]]*env_file:" &&
   grep -A40 "deployment:" "$COMPOSE_FILE" | grep -q "\.env\.shared" &&
   grep -A40 "deployment:" "$COMPOSE_FILE" | grep -q "\.env\.test"; then
    echo -e "${GREEN}✓ Base compose deployment service loads .env.shared + .env.test (deterministic defaults)${NC}"
else
    echo -e "${RED}✗ Base compose deployment service must load .env.shared + .env.test${NC}"
    exit 1
fi

if [ -f "$MANUAL_COMPOSE_FILE" ]; then
    echo -e "${GREEN}✓ Manual compose override file exists${NC}"
else
    echo -e "${RED}✗ Manual compose override file is missing${NC}"
    exit 1
fi

if grep -q "^[[:space:]]*app-fixture-prepare:" "$MANUAL_COMPOSE_FILE" &&
   grep -q "^[[:space:]]*deployment:" "$MANUAL_COMPOSE_FILE" &&
   grep -q "env_file:[[:space:]]*!override" "$MANUAL_COMPOSE_FILE" &&
   grep -q "^[[:space:]]*-[[:space:]]*\.env\.shared$" "$MANUAL_COMPOSE_FILE" &&
   grep -q "\.env\.manual" "$MANUAL_COMPOSE_FILE"; then
    echo -e "${GREEN}✓ Manual compose override replaces env files with .env.shared + .env.manual${NC}"
else
    echo -e "${RED}✗ Manual compose override must use !override with .env.shared + .env.manual for app-fixture-prepare/deployment${NC}"
    exit 1
fi

if grep -q "deployment-secure:" "$MANUAL_COMPOSE_FILE" ||
   grep -q "mysql:" "$MANUAL_COMPOSE_FILE" ||
   grep -q "minio:" "$MANUAL_COMPOSE_FILE"; then
    echo -e "${RED}✗ Manual compose override should not modify non-deployment services${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Manual compose override is scoped to app-fixture-prepare and deployment only${NC}"
fi

if grep -q "^tests/\.env\.manual$" "$GITIGNORE_FILE"; then
    echo -e "${GREEN}✓ Local manual env override file is gitignored${NC}"
else
    echo -e "${RED}✗ .gitignore must include tests/.env.manual${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Integration compose startup tests passed${NC}"
