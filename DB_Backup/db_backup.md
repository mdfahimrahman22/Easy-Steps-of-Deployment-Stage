# Database Backup & S3 Upload Documentation

This project includes an automated script to backup your PostgreSQL database and upload the resulting dump file to AWS S3.

## 📁 Backup Script
The primary script is `backup_db_to_s3.sh`.

- **Output Format**: PostgreSQL Custom Format (`.dump`)
- **Storage Location**: 
  - Local: `/db_backups/`
  - S3: `s3://[YOUR_BUCKET]/db_backups/`
- **Naming Convention**: `db_backup_YYYYMMDD_HHMMSS.dump`

---

## 🛠️ Prerequisites
Ensure your Linux server has the following installed:
1. **PostgreSQL Client**: For the `pg_dump` command.
   ```bash
   sudo apt install postgresql-client
   ```
2. **AWS CLI**: For uploading to S3.
   ```bash
   sudo apt install awscli
   ```

---

## 🚀 Setup & Execution

### 1. Permissions
Make the script executable:
```bash
chmod +x backup_db_to_s3.sh
```

### 2. Configuration
The script automatically reads credentials from the `.env` file in the same directory. Ensure your `.env` contains:
```env
# Database
DB_NAME=...
DB_USER=...
DB_PASSWORD=...
DB_HOST=...
DB_PORT=5432

# AWS S3
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_STORAGE_BUCKET_NAME=...
AWS_STORAGE_BUCKET_REGION=...
```

### 3. Manual Run
To run the backup once and see the output:
```bash
./backup_db_to_s3.sh
```

---

## 🌙 Running in the Background
If you want to close your terminal session while the backup is running, use `nohup`. This ensures the script finishes even if you disconnect.

### Start the Backup
```bash
nohup ./backup_db_to_s3.sh > backup.log 2>&1 &
```
- `> backup.log`: Saves all output to a log file.
- `&`: Runs the process in the background.

### Monitor Progress
To see the backup progress in real-time:
```bash
tail -f backup.log
```

### Stopping the Backup
If you need to stop a backup that is running in the background:
```bash
pkill -f backup_db_to_s3.sh
```
Or find the PID manually and kill it:
1. `ps aux | grep backup_db_to_s3.sh`
2. `kill [PID_NUMBER]`

---

## ⏰ Automation (Cron Job)
To schedule this backup to run automatically (e.g., every day at 2 AM), add it to your crontab:

1. Open crontab:
   ```bash
   crontab -e
   ```
2. Add the following line (replace `/path/to/your/project` with the actual path):
   ```cron
   0 2 * * * cd /path/to/your/project && ./backup_db_to_s3.sh >> backup_cron.log 2>&1
   ```

---

## 🛡️ Security Note
- The script **does not contain any hardcoded passwords**.
- It uses a secure environment variable (`PGPASSWORD`) during execution to avoid password prompts.
- Ensure your `.env` file has restricted permissions (`chmod 600 .env`).

---

## ♻️ Restoring from a Backup

Use the `restore_db_from_s3.sh` script to restore the database from any backup stored in S3.

> ⚠️ **This will DESTROY all existing data** in the target database. Only use this on a fresh/new DB or when you explicitly want to overwrite.

---

### Prerequisites

Make sure you have:
1. **PostgreSQL Client** (`pg_restore`, `psql`) installed.
2. **AWS CLI** installed and your `.env` configured (same as backup).

---

### Step 1 — List Available Backups

SSH into your server and list backups stored in S3:
```bash
aws s3 ls s3://YOUR_BUCKET/db_backups/
```
Pick the filename you want to restore, e.g. `db_backup_20260413_103000.dump`.

---

### Step 2 — Make the Script Executable
```bash
chmod +x restore_db_from_s3.sh
```

---

### Step 3 — Run the Restore

The script supports three ways to specify which backup to restore:

#### Option 1: Auto-detect Latest from S3 (Recommended)
Automatically finds and downloads the most recent backup from your S3 bucket.
```bash
./restore_db_from_s3.sh
```

#### Option 2: Specify S3 Filename
Downloads and restores a specific file from S3.
```bash
./restore_db_from_s3.sh db_backup_20260413_103000.dump
```

#### Option 3: Use Local File
Directly restores from a local file on your server (skips S3 entirely).
```bash
./restore_db_from_s3.sh /absolute/path/to/db_backup_20260413_103000.dump
```

---

**What the script does:**
1. Reads credentials from `.env` (same file used by backup).
2. Downloads the `.dump` file from S3 to `./db_backups/` locally (skips download if file is already present).
3. Asks for confirmation before destroying the existing DB.
4. **Terminates all active connections** to the database.
5. **Drops** the existing database and **creates a fresh one**.
6. Runs `pg_restore` with `--no-owner --no-privileges` flags.

---

### Step 4 — Post-Restore Steps

After a successful restore, run the following Django commands if needed:
```bash
# Apply any pending migrations (if schema changed since backup)
python manage.py migrate

# (Optional) Create a new superuser
python manage.py createsuperuser
```

---

### Running in Background (for large DBs)

For large databases, run the restore in the background so it continues even if you disconnect:
```bash
nohup ./restore_db_from_s3.sh db_backup_20260413_103000.dump > restore.log 2>&1 &
tail -f restore.log
```

---

### Troubleshooting

| Issue | Cause | Fix |
|---|---|---|
| `pg_restore` exits with warnings | Non-critical errors (e.g. missing extensions, role mismatches) | Usually safe to ignore; check log output |
| `DROP DATABASE` fails | Active connections to the DB | Script auto-terminates connections; retry the script |
| S3 download fails | Wrong credentials or bucket name | Check `.env` AWS keys and bucket name |
| `createdb` permission error | DB user lacks `CREATEDB` privilege | Run `ALTER USER your_user CREATEDB;` as Postgres superuser |

