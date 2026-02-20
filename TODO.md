# TODO List

## MySQL SSL Certificate Handling

### Investigate proper solution for MySQL 8.0 SSL certificates

**Current workaround:**
Using `--skip-ssl-verify-server-cert` flag in `scripts/import-database.sh` to bypass SSL certificate validation.

**Problem:**
MySQL 8.0 uses SSL by default with self-signed certificates. The MariaDB client in the devpanel/php base image attempts SSL validation and fails with:
```
ERROR 2026 (HY000): TLS/SSL error: self-signed certificate in certificate chain
```

**Why this workaround is not ideal:**
While `--skip-ssl-verify-server-cert` maintains encryption (better than `--skip-ssl`), it bypasses certificate validation entirely. This is a security trade-off appropriate for test/development but not a proper solution.

**Proper solutions to investigate:**
1. **Configure MariaDB client to trust the MySQL self-signed CA**
   - Examine if MySQL 8.0 container provides its CA certificate
   - Configure MariaDB client to use that CA via `--ssl-ca` option
   - This would maintain both encryption AND validation

2. **Check if docker_publish_action solves this differently**
   - They use `devpanel/php:8.3-base-ai` (different base image)
   - May have MySQL client configuration we don't have
   - Investigate what's different in their setup

3. **Consider if GitHub Actions MySQL service has different defaults**
   - GitHub Actions services might configure MySQL differently
   - Test locally with exact same MySQL configuration

**Action items:**
- [ ] Investigate MySQL 8.0 container CA certificate location
- [ ] Test with `--ssl-ca` pointing to MySQL's CA
- [ ] Compare docker_publish_action's base image configuration
- [ ] Document findings and implement proper fix

**References:**
- MySQL SSL docs: https://dev.mysql.com/doc/refman/8.0/en/using-encrypted-connections.html
- MariaDB client SSL options: https://mariadb.com/kb/en/mysql-command-line-client/

---

## File Permissions and User Namespace Differences

### Why file proxy tests pass locally but fail in CI

**The Issue:**
File proxy tests require Apache (running as `www-data` UID 33) to write files to directories that may be owned by different users depending on the environment.

**Local Environment (VSCode/Developer Machine):**
- Developer's UID is often 1000 (same as container's `www` user)
- When you mount `./fixtures/app:/var/www/html`, files created on host are owned by UID 1000
- Container's deployment-entrypoint fixes ownership to `www:www` (1000:1000)
- Files end up owned by `www:www-data` with group-writable permissions
- Apache (www-data) CAN write because it's in the www-data group

**CI Environment (GitHub Actions):**
- GitHub Actions runner UID is 1001 (not 1000)
- When tests mount `./fixtures/app:/var/www/html`, files are owned by 1001:1001
- Container's deployment-entrypoint changes ownership to `www:www` (1000:1000)
- **Without the fix:** Files owned `www:www` with 755 permissions - Apache (www-data) CANNOT write
- **With the fix:** deployment-entrypoint sets group to www-data and adds g+w permissions - Apache CAN write

**The Fix (commit 4bfa704):**
```bash
# deployment-entrypoint.sh
sudo chown -R ":www-data" "$APP_ROOT"  # Set group to www-data
sudo chmod -R g+w "$WEB_ROOT"  # Make group-writable
```

**Why you didn't see this locally:**
Your local UID (probably 1000) matches the container's `www` user UID, so the ownership was already compatible. In CI, the runner UID (1001) doesn't match, exposing the permission issue.

**Update (commits e863fe1, d1ab83c):**
Replaced the complex group ownership workaround with base image's "less secure mode" - but only for testing.

---

## Apache Less Secure Mode (Test Environment Only)

### Configuration

Integration tests use the base image's "less secure mode" to simplify file permissions by configuring Apache to run as the container user (`www`) instead of the default `www-data` user.

**Configuration** (in `tests/docker-compose.test.yml`):
```yaml
environment:
  APACHE_RUN_USER: www
  APACHE_RUN_GROUP: www
```

**Why this works:**
- Container runs as `www` user (UID 1000)
- Apache runs as `www` user (UID 1000) 
- Same user = no permission mismatches
- Files use standard 0755/0644 permissions

**Why only for testing:**
- Running Apache as the application user gives it more privileges than necessary
- Production deployments should use separate, less-privileged Apache user (www-data)
- This is appropriate for dev/test but not production

### Production Deployments

For production, the Dockerfile does NOT set APACHE_RUN_USER/APACHE_RUN_GROUP, so Apache runs as `www-data` (the base image default). You would need to either:
1. Ensure files are owned by `www-data` group with group-writable permissions, OR
2. Run the entrypoint as root to fix ownership before switching to application user, OR
3. Use named volumes instead of bind mounts

---

## Platform Specifications

### Remove platform specification from tests when base image supports ARM64

**Files affected:**
- `tests/docker-build-test.sh` (line ~47)
- `tests/docker-compose.test.yml` (line ~70)

**Description:**
Currently, we explicitly specify `--platform linux/amd64` in tests because the devpanel/php base image is not available for linux/arm64. Once the base image supports ARM64:

1. Remove `--platform linux/amd64` from the docker build command in `tests/docker-build-test.sh`
2. Remove `platform: linux/amd64` from the deployment service in `tests/docker-compose.test.yml`

This will allow tests to run natively on any architecture without forcing a specific platform.

**Tracking:**
- Related to devpanel/php base image ARM64 support
- Test on ARM64 systems after removing to ensure compatibility
