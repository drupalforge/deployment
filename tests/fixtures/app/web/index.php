<?php
// Test application for deployment validation

// Set up error reporting
error_reporting(E_ALL);
ini_set('display_errors', 1);

// Get request path
$request_path = $_SERVER['REQUEST_URI'] ?? '/';
$script_name = isset($_SERVER['SCRIPT_NAME']) ? dirname($_SERVER['SCRIPT_NAME']) : '/';

// Echo basic response
echo "<!DOCTYPE html>\n";
echo "<html>\n<head><title>Test Application</title></head>\n<body>\n";
echo "<h1>Deployment Test Application</h1>\n";
echo "<p>Request: " . htmlspecialchars($request_path) . "</p>\n";
echo "<p>Document Root: " . htmlspecialchars($_SERVER['DOCUMENT_ROOT'] ?? 'not set') . "</p>\n";

// Check if database exists
$db_host = getenv('DB_HOST') ?: 'localhost';
$db_user = getenv('DB_USER') ?: 'drupal';
$db_pass = getenv('DB_PASSWORD') ?: 'drupal_password';
$db_name = getenv('DB_NAME') ?: 'drupaldb';

try {
    $pdo = new PDO(
        "mysql:host=$db_host;dbname=$db_name",
        $db_user,
        $db_pass
    );
    $result = $pdo->query("SELECT COUNT(*) as user_count FROM users");
    $row = $result->fetch();
    echo "<p><strong>✓ Database connected</strong> - Users: " . $row['user_count'] . "</p>\n";
} catch (Exception $e) {
    echo "<p><strong>✗ Database error:</strong> " . htmlspecialchars($e->getMessage()) . "</p>\n";
}

// List files in sites/default/files if it exists
$files_dir = dirname(__DIR__) . '/sites/default/files';
if (is_dir($files_dir)) {
    echo "<p><strong>Files directory exists</strong></p>\n";
    $files = array_diff(scandir($files_dir), ['.', '..']);
    if (!empty($files)) {
        echo "<ul>\n";
        foreach ($files as $file) {
            echo "  <li>" . htmlspecialchars($file) . "</li>\n";
        }
        echo "</ul>\n";
    } else {
        echo "<p>No files yet</p>\n";
    }
}

echo "</body>\n</html>\n";
