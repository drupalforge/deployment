#!/bin/bash
set -e

# S3 Database Import Script
# This script imports a database from an S3 bucket into MySQL
# 
# Required environment variables:
#   DB_HOST - Database host
#   DB_USER - Database user
#   DB_PASSWORD - Database password
#   DB_NAME - Database name
#   S3_BUCKET - S3 bucket name (e.g., 'my-bucket')
#   S3_DATABASE_PATH - Path to database dump in S3 (e.g., 'dumps/site.sql.gz')
#   AWS_REGION - AWS region (default: us-east-1)
#   AWS_ACCESS_KEY_ID - AWS access key (uses instance role if not provided)
#   AWS_SECRET_ACCESS_KEY - AWS secret key (uses instance role if not provided)

# Function to log messages
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Function to log errors
error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
  return 1
}

# Validate required environment variables
validate_env() {
  local required_vars=("DB_HOST" "DB_USER" "DB_PASSWORD" "DB_NAME" "S3_BUCKET" "S3_DATABASE_PATH")
  
  for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
      error "Required environment variable not set: $var"
      return 1
    fi
  done
  
  # Set AWS_REGION default
  AWS_REGION="${AWS_REGION:-us-east-1}"
  export AWS_REGION

  # AWS CLI primarily reads AWS_DEFAULT_REGION; keep both set for compatibility.
  AWS_DEFAULT_REGION="$AWS_REGION"
  export AWS_DEFAULT_REGION

  # Avoid metadata service lookups in containers that can cause long startup delays.
  AWS_EC2_METADATA_DISABLED="true"
  export AWS_EC2_METADATA_DISABLED
}

# Check if database already has tables
database_exists() {
  local table_count
  table_count=$(mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
    --skip-ssl-verify-server-cert \
    -se "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB_NAME';" 2>/dev/null || echo "0")
  
  if [ "$table_count" -gt 0 ]; then
    return 0  # Database exists
  else
    return 1  # Database is empty
  fi
}

# Download and import database from S3
import_from_s3() {
  local temp_dump
  local s3_url="s3://${S3_BUCKET}/${S3_DATABASE_PATH}"
  
  temp_dump=$(mktemp)
  trap "rm -f $temp_dump" EXIT
  
  log "Downloading database from S3: $s3_url"
  
  # Build aws s3 cp command with optional endpoint URL for S3-compatible services (e.g., MinIO)
  local aws_cmd="aws s3 cp"
  if [ -n "$AWS_S3_ENDPOINT" ]; then
    aws_cmd="$aws_cmd --endpoint-url=$AWS_S3_ENDPOINT"
    log "Using custom S3 endpoint: $AWS_S3_ENDPOINT"
  fi
  
  # Download from S3 using aws cli
  if ! $aws_cmd "$s3_url" "$temp_dump"; then
    error "Failed to download database from S3"
    return 1
  fi
  
  log "Database downloaded, importing to MySQL..."
  
  # Determine if file is gzipped
  if [[ "$S3_DATABASE_PATH" == *.gz ]]; then
    gzip -d -c "$temp_dump" | mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
      --skip-ssl-verify-server-cert
  else
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" \
      --skip-ssl-verify-server-cert < "$temp_dump"
  fi
  
  if [ $? -eq 0 ]; then
    log "Database imported successfully"
    return 0
  else
    error "Failed to import database"
    return 1
  fi
}

# Main execution
main() {
  log "Starting S3 database import process"
  
  # Validate environment
  if ! validate_env; then
    log "Skipping database import: required environment variables not set"
    return 0
  fi
  
  # Wait for database to be ready
  log "Waiting for database to be ready at $DB_HOST:${DB_PORT:-3306}..."
  local max_attempts=30
  local attempt=0
  
  while [ $attempt -lt $max_attempts ]; do
    if mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" \
        --skip-ssl-verify-server-cert -e "SELECT 1" &>/dev/null; then
      log "Database is ready"
      break
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
  
  if [ $attempt -eq $max_attempts ]; then
    error "Database failed to become ready after $(($max_attempts * 2)) seconds"
    return 1
  fi
  
  # Check if database is already populated
  if database_exists; then
    log "Database already has tables, skipping import"
    return 0
  fi
  
  # Import from S3
  if import_from_s3; then
    log "Database import completed successfully"
    return 0
  else
    error "Database import failed"
    return 1
  fi
}

# Run main function
main "$@"
