<?php
/**
 * Proxy file download handler
 * 
 * For requests to missing files, downloads from origin server and saves to the real path.
 * Subsequent requests serve the file directly from disk.
 */

// Get the requested path
$requested_uri = $_SERVER['REQUEST_URI'] ?? '/';

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

// Build paths
$target_path = $web_root . $requested_path;

// Security check: ensure target is within web root
$real_web_root = realpath($web_root);
$real_target = realpath(dirname($target_path));
if ($real_target === false || strpos($real_target, $real_web_root) !== 0) {
    http_response_code(400);
    die("Target path outside web root\n");
}

// Create parent directory if needed
$target_dir = dirname($target_path);
if (!is_dir($target_dir)) {
    if (!mkdir($target_dir, 0755, true)) {
        http_response_code(500);
        die("Failed to create directory: $target_dir\n");
    }
}

// Build origin URL (remove trailing slash from origin, add leading slash to requested path)
$origin_url = rtrim($origin_url, '/');
$full_url = $origin_url . $requested_path;

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

// Write file to disk
if (file_put_contents($target_path, $file_content) === false) {
    http_response_code(500);
    die("Failed to write file to $target_path\n");
}

// Set permissions
chmod($target_path, 0644);
@chown($target_path, 'www-data');
@chgrp($target_path, 'www-data');

// Serve the file
if (file_exists($target_path) && is_file($target_path)) {
    // Determine MIME type
    $finfo = finfo_open(FILEINFO_MIME_TYPE);
    $mime_type = finfo_file($finfo, $target_path) ?: 'application/octet-stream';
    finfo_close($finfo);
    
    header('Content-Type: ' . $mime_type);
    header('Content-Length: ' . filesize($target_path));
    readfile($target_path);
    exit(0);
}

// Should not reach here
http_response_code(500);
die("Failed to serve file\n");
