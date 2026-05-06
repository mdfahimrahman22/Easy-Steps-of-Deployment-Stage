#!/bin/bash

# --- Restore Database from AWS S3 Backup ---
# This script downloads a backup from S3 and restores it to a PostgreSQL database.
# It reads all credentials from the .env file.
# Do NOT hardcode secrets here.

# Get the directory of the script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# ============================================================
# USAGE:
#   ./restore_db_from_s3.sh                          # Auto: downloads latest backup from S3
#   ./restore_db_from_s3.sh <backup_filename>         # Downloads specific file from S3
#   ./restore_db_from_s3.sh <absolute_local_path>     # Uses a local file directly (no S3 download)
#
# Examples:
#   ./restore_db_from_s3.sh
#   ./restore_db_from_s3.sh db_backup_20260413_103000.dump
#   ./restore_db_from_s3.sh /mnt/backups/db_backup_20260413_103000.dump
# ============================================================

# 1. Load variables from .env manually to handle special characters
if [ -f "$DIR/.env" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        key="${line%%=*}"
        value="${line#*=}"

        key=$(echo "$key" | xargs)

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

# 2. Assign values from environment
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

BACKUP_DIR="$DIR/db_backups"
mkdir -p "$BACKUP_DIR"

# 4. Set AWS credentials for this session (needed for S3 modes)
export AWS_ACCESS_KEY_ID="$AWS_KEY"
export AWS_SECRET_ACCESS_KEY="$AWS_SECRET"
export AWS_DEFAULT_REGION="$AWS_REGION"

# 5. Resolve the backup file to restore
# Mode A: Local file path provided (file already exists on disk)
if [ -n "$1" ] && [ -f "$1" ]; then
    FILE_PATH="$1"
    FILE_NAME=$(basename "$FILE_PATH")
    echo "Using local backup file: $FILE_PATH"

# Mode B: Specific S3 filename provided (bare filename, not a path)
elif [ -n "$1" ]; then
    FILE_NAME="$1"
    FILE_PATH="${BACKUP_DIR}/${FILE_NAME}"

    if [ -f "$FILE_PATH" ]; then
        echo "Local file already exists, skipping S3 download: $FILE_PATH"
    else
        echo "Downloading from S3: s3://$AWS_BUCKET/db_backups/$FILE_NAME ..."
        aws s3 cp "s3://$AWS_BUCKET/db_backups/$FILE_NAME" "$FILE_PATH"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to download '$FILE_NAME' from S3!"
            exit 1
        fi
        echo "Download successful: $FILE_PATH"
    fi

# Mode C: No argument — auto-detect and download the latest backup from S3
else
    echo "No backup file specified. Finding latest backup in S3..."
    FILE_NAME=$(aws s3 ls "s3://$AWS_BUCKET/db_backups/" \
        | grep '\.dump$' \
        | sort -k1,2 \
        | tail -1 \
        | awk '{print $NF}')

    if [ -z "$FILE_NAME" ]; then
        echo "Error: No .dump files found in s3://$AWS_BUCKET/db_backups/"
        exit 1
    fi

    FILE_PATH="${BACKUP_DIR}/${FILE_NAME}"
    echo "Latest backup found: $FILE_NAME"

    if [ -f "$FILE_PATH" ]; then
        echo "Local file already exists, skipping S3 download: $FILE_PATH"
    else
        echo "Downloading from S3: s3://$AWS_BUCKET/db_backups/$FILE_NAME ..."
        aws s3 cp "s3://$AWS_BUCKET/db_backups/$FILE_NAME" "$FILE_PATH"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to download latest backup from S3!"
            exit 1
        fi
        echo "Download successful: $FILE_PATH"
    fi
fi

echo "--------------------------------------------------"
echo "DB Restore Started at: $(date)"
echo "Backup file  : $FILE_NAME"
echo "File path    : $FILE_PATH"
echo "Target DB    : $DB_NAME on $DB_HOST:$DB_PORT"
echo "--------------------------------------------------"

# 7. Set Postgres password for non-interactive auth
export PGPASSWORD="$DB_PASS"
# 8. Handle Database Creation/Existence
echo ""
echo "Checking if database '$DB_NAME' exists..."
DB_EXISTS=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'")
IS_NEW_DB=0

if [ "$DB_EXISTS" == "1" ]; then
    echo "Database '$DB_NAME' already exists. Skipping drop/create to avoid permission issues."
    echo "The restore will overwrite/update existing objects in the current database."
else
    IS_NEW_DB=1
    echo "Database '$DB_NAME' does not exist. Attempting to create it..."
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres \
        -c "CREATE DATABASE \"$DB_NAME\" OWNER \"$DB_USER\";"

    if [ $? -eq 0 ]; then
        echo "Database created successfully. Applying permissions..."
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
            -c "GRANT CONNECT ON DATABASE \"$DB_NAME\" TO \"$DB_USER\";" \
            -c "ALTER DATABASE \"$DB_NAME\" OWNER TO \"$DB_USER\";" \
            -c "GRANT USAGE, CREATE ON SCHEMA public TO \"$DB_USER\";" \
            -c "GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO \"$DB_USER\";" \
            -c "GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO \"$DB_USER\";" \
            -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO \"$DB_USER\";" \
            -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO \"$DB_USER\";"
        echo "Permissions applied successfully."
    else
        echo "Error: Failed to create the database '$DB_NAME'!"
        echo "Root Cause: Your DB user likely lacks the 'CREATEDB' privilege and the DB doesn't exist yet."
        echo "Fix: Please create the database manually (as a superuser) or grant '$DB_USER' the CREATEDB permission."
        unset PGPASSWORD
        exit 1
    fi
fi

# 9. Restore using pg_restore
# IMPORTANT: --clean must NOT be used on a freshly created empty database.
# It causes pg_restore to enter "implied data-only restore" mode (skipping schema/DDL),
# resulting in no tables being created.
# --clean is only needed when restoring into an existing database with pre-existing objects.
echo ""
echo "Restoring database from: $FILE_PATH ..."

if [ "$IS_NEW_DB" -eq 0 ]; then
    echo "Existing database detected — using --clean --if-exists to replace all objects."
    pg_restore \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        --clean \
        --if-exists \
        --no-owner \
        --no-privileges \
        -v \
        "$FILE_PATH"
else
    echo "Fresh database detected — performing full schema + data restore."
    pg_restore \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$DB_NAME" \
        --no-owner \
        --no-privileges \
        -v \
        "$FILE_PATH"
fi

RESTORE_EXIT=$?

# Cleanup password from memory
unset PGPASSWORD

echo ""
echo "--------------------------------------------------"
if [ $RESTORE_EXIT -eq 0 ]; then
    echo "Restore Completed Successfully at: $(date)"
    echo ""
    echo "Next steps:"
    echo "  1. Run Django migrations if needed: python manage.py migrate"
    echo "  2. Create a superuser if needed:    python manage.py createsuperuser"
else
    echo "Warning: pg_restore finished with warnings/errors (exit code: $RESTORE_EXIT)."
    echo "  - 'unrecognized configuration parameter \"transaction_timeout\"' -> safe to ignore (PG version mismatch)"
    echo "  - 'missing extension' errors -> usually safe to ignore"
    echo "  - Check above output for any critical errors (e.g. missing tables or data)."
fi
echo "--------------------------------------------------"
