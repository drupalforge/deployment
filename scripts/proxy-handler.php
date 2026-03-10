<?php
/**
 * Proxy file download handler
 * 
 * For requests to missing files, downloads from origin server and saves to the real path.
 * Subsequent requests serve the file directly from disk.
 */

// Get the requested path from Apache rewrite context.
// PROXY_ORIG_PATH is set explicitly by the RewriteRule [E=PROXY_ORIG_PATH:/$1] flag,
// capturing the relative request path and prepending a slash. This is the most reliable
// source when PHP runs via PHP-FPM FastCGI, where REQUEST_URI may contain the rewritten
// URL rather than the original. REDIRECT_URL is a fallback for other configurations.
$requested_uri = $_SERVER['PROXY_ORIG_PATH']
    ?? ($_SERVER['REDIRECT_URL'] ?? ($_SERVER['REQUEST_URI'] ?? '/'));

// Remove query string if present
$requested_path = strtok($requested_uri, '?');

// Security check: reject suspicious paths
if (strpos($requested_path, '..') !== false || $requested_path === '/') {
    http_response_code(400);
    die("Invalid request path\n");
}

// Get origin URL from environment
$origin_url = getenv('ORIGIN_URL');
if (!$origin_url) {
    http_response_code(503);
    die("Origin URL not configured. Set ORIGIN_URL environment variable.\n");
}

// Get web root (remove trailing slash)
$web_root = getenv('WEB_ROOT') ?: ($_SERVER['DOCUMENT_ROOT'] ?? '/var/www/html');
$web_root = rtrim($web_root, '/');

// Handle Drupal image styles: if requesting a styled image that doesn't exist,
// fetch the original file instead so Drupal can generate the style.
// Pattern: /sites/default/files/styles/{style_name}/public/{original_path}
// Original: /sites/default/files/{original_path}
// Always redirect back to the styled URL so Drupal can generate the derivative;
// only download the original from origin when it is not already on disk.
$download_path = $requested_path;
$is_image_style = false;
if (preg_match('#^(/[^/]+/[^/]+/files)/styles/[^/]+/public/(.+)$#', $requested_path, $matches)) {
    $download_path = $matches[1] . '/' . $matches[2];
    $is_image_style = true;
}

// Derive save path from download_path (original path, not styled image path).
$save_path = $web_root . $download_path;
$save_dir  = dirname($save_path);

// Security check: ensure save target is within web root.
// For first-time proxy requests, target directories may not exist yet, so resolve
// the nearest existing parent path and validate that parent against web root.
$real_web_root = realpath($web_root);
if ($real_web_root === false) {
    http_response_code(500);
    die("Web root path is invalid\n");
}

$probe_dir = $save_dir;
$real_save_parent = false;
while ($probe_dir !== '/' && $probe_dir !== '' && $probe_dir !== '.') {
    $resolved = realpath($probe_dir);
    if ($resolved !== false) {
        $real_save_parent = $resolved;
        break;
    }
    $probe_dir = dirname($probe_dir);
}

if ($real_save_parent === false || strpos($real_save_parent, $real_web_root) !== 0) {
    http_response_code(400);
    die("Target path outside web root\n");
}

// For image style URLs: if the original file is already on disk, redirect back to
// the styled URL so Drupal can generate the derivative without re-downloading.
if ($is_image_style && file_exists($save_path)) {
    $query_string = $_SERVER['REDIRECT_QUERY_STRING'] ?? ($_SERVER['QUERY_STRING'] ?? '');
    $redirect_uri = $requested_path . ($query_string !== '' ? '?' . $query_string : '');
    header('Location: ' . $redirect_uri, true, 302);
    exit(0);
}

// Create parent directory if needed
if (!is_dir($save_dir)) {
    if (!mkdir($save_dir, 0755, true)) {
        http_response_code(500);
        die("Failed to create directory: $save_dir\n");
    }
    // Ensure directory is group-writable for Apache
    @chmod($save_dir, 0775);
}

// Build origin URL (remove trailing slash from origin, add leading slash to download path)
$origin_url = rtrim($origin_url, '/');
$full_url = $origin_url . $download_path;

// Download file using curl
$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, $full_url);
curl_setopt($ch, CURLOPT_TIMEOUT, 30);
curl_setopt($ch, CURLOPT_FAILONERROR, true);
curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);

$file_content = curl_exec($ch);
$curl_error = curl_error($ch);
$http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

// Check for download errors
if ($file_content === false) {
    http_response_code(502);
    die("Failed to download from origin: $curl_error\n");
}

if ($http_code >= 400) {
    http_response_code(502);
    die("Origin returned HTTP $http_code\n");
}

// Write file to disk at the original (non-styled) path
if (file_put_contents($save_path, $file_content) === false) {
    http_response_code(500);
    die("Failed to write file to $save_path\n");
}

// Set standard file permissions
chmod($save_path, 0644);

// File is now on disk. Redirect so Apache serves it directly with correct MIME detection
// via mod_mime. For image styles the redirect returns to the styled URL so Drupal can
// generate the derivative from the original that is now on disk.
$query_string = $_SERVER['REDIRECT_QUERY_STRING'] ?? ($_SERVER['QUERY_STRING'] ?? '');
$redirect_uri = $requested_path . ($query_string !== '' ? '?' . $query_string : '');
header('Location: ' . $redirect_uri, true, 302);
exit(0);
