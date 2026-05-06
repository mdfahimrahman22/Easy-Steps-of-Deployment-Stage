#!/bin/bash

# --- Database Backup to AWS S3 (Secure) ---
# This script reads all credentials from the .env file.
# Do NOT hardcode secrets here.

# Get the directory of the script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# 1. Load variables from .env manually to handle special characters (like '(' and ')')
if [ -f "$DIR/.env" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        
        # Split by the first '='
        key="${line%%=*}"
        value="${line#*=}"
        
        # Trim whitespace from key
        key=$(echo "$key" | xargs)
        
        # Remove surrounding quotes from value if they exist
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        
        export "$key"="$value"
    done < "$DIR/.env"
else
    echo "Error: .env file not found in $DIR"
    exit 1
fi

# 2. Assign values from environment (loaded from .env)
DB_NAME="$DB_NAME"
DB_USER="$DB_USER"
DB_PASS="$DB_PASSWORD"
DB_HOST="$DB_HOST"
DB_PORT="$DB_PORT"

AWS_KEY="$AWS_ACCESS_KEY_ID"
AWS_SECRET="$AWS_SECRET_ACCESS_KEY"
AWS_BUCKET="$AWS_STORAGE_BUCKET_NAME"
AWS_REGION="$AWS_STORAGE_BUCKET_REGION"

# 3. Check for required variables
REQUIRED_VARS=("DB_NAME" "DB_USER" "DB_PASSWORD" "DB_HOST" "DB_PORT" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_STORAGE_BUCKET_NAME" "AWS_STORAGE_BUCKET_REGION")

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Required variable $var is missing in .env file"
        exit 1
    fi
done

# Local setup
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$DIR/db_backups"
FILE_NAME="db_backup_${DATE}.dump"
FILE_PATH="${BACKUP_DIR}/${FILE_NAME}"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

echo "--------------------------------------------------"
echo "SQL Backup Started at: $(date)"
echo "--------------------------------------------------"

# 1. Perform pg_dump
export PGPASSWORD="$DB_PASS"
echo "Dumping database: $DB_NAME..."

# Flags:
#   -F c          : Custom format (required for pg_restore)
#   --no-owner    : Skip ownership statements (avoids permission errors during restore)
#   --no-privileges: Skip GRANT/REVOKE statements (avoids permission errors during restore)
#   --schema      : Explicitly include schema (DDL) — ensures tables/indexes are backed up
pg_dump \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -F c \
    --no-owner \
    --no-privileges \
    -f "$FILE_PATH"

if [ $? -eq 0 ]; then
    echo "Backup local file created: $FILE_PATH"

    # Verify the dump contains schema (DDL), not just data
    SCHEMA_COUNT=$(pg_restore -l "$FILE_PATH" | grep -c '^[0-9].*TABLE ')
    if [ "$SCHEMA_COUNT" -eq 0 ]; then
        echo "WARNING: Dump appears to contain NO schema (TABLE definitions)!"
        echo "This usually means '$DB_USER' lacks schema visibility on the database."
        echo "Tip: Run pg_dump as a superuser or ensure '$DB_USER' owns the tables."
        echo "Aborting upload to prevent a bad backup from reaching S3."
        rm -f "$FILE_PATH"
        exit 1
    fi
    echo "Schema check passed: $SCHEMA_COUNT table(s) found in dump."
    
    # 2. Upload to S3
    echo "Uploading to AWS S3 (Bucket: $AWS_BUCKET)..."
    
    # Export AWS credentials for this session (already exported from .env, but ensuring they are standard for AWS CLI)
    export AWS_ACCESS_KEY_ID="$AWS_KEY"
    export AWS_SECRET_ACCESS_KEY="$AWS_SECRET"
    export AWS_DEFAULT_REGION="$AWS_REGION"

    aws s3 cp "$FILE_PATH" "s3://$AWS_BUCKET/db_backups/$FILE_NAME"

    if [ $? -eq 0 ]; then
        echo "Upload successful to S3: s3://$AWS_BUCKET/db_backups/$FILE_NAME"
        # Optional: Remove local file after successful upload to save server space
        # rm "$FILE_PATH"
        # echo "Local file removed."
    else
        echo "Error: S3 upload failed!"
        exit 1
    fi
else
    echo "Error: Database backup failed!"
    exit 1
fi

# Cleanup password from memory
unset PGPASSWORD

echo "--------------------------------------------------"
echo "Backup Completed Successfully at: $(date)"
echo "--------------------------------------------------"
