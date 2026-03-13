#!/bin/bash
set -e

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$TEST_DIR/docker-compose.test.yml"
INTEGRATION_SCRIPT="$TEST_DIR/integration-test.sh"

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

if grep -q "drupal/recommended-project.git" "$COMPOSE_FILE"; then
    echo -e "${GREEN}✓ Fixture init restores Drupal project when fixture is incomplete${NC}"
else
    echo -e "${RED}✗ Compose file is missing Drupal fixture initialization command${NC}"
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

echo -e "${GREEN}✓ Integration compose startup tests passed${NC}"
