<?php

$databases['default']['default']['database'] = getenv('DB_NAME');
$databases['default']['default']['username'] = getenv('DB_USER');
$databases['default']['default']['password'] = getenv('DB_PASSWORD');
$databases['default']['default']['host'] = getenv('DB_HOST');
$databases['default']['default']['port'] = getenv('DB_PORT');
$databases['default']['default']['driver'] = getenv('DB_DRIVER');
$databases['default']['default']['isolation_level'] = 'READ COMMITTED';
if (empty($settings['hash_salt'])) {
  $settings['hash_salt'] = hash('sha256', serialize($databases));
}
$settings['config_sync_directory'] ??= '../config/sync';
$settings['file_private_path'] ??= '../private';
$settings['trusted_host_patterns'][] = getenv('DP_HOSTNAME') ?: '.*';
