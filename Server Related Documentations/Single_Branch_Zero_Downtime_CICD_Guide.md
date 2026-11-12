# Single-Branch (main) Zero-Downtime CI/CD Deployment Guide

This documentation provides a clean, production-ready guide for setting up **automated CI/CD pipelines with Zero-Downtime deployments** for single-branch projects (e.g., `main` branch auto-deployment) using a **GitHub Self-Hosted Runner** on servers with **restricted SSH (Port 22)**.

> **Example Reference Project:** `sohay-ielts` (NodeJS / TurboRepo / Docker / Prisma) or any standard single-branch full-stack / backend repository.

---

## 1. Architecture Overview

```
                      [ Git Push to main branch ]
                                  │
                                  ▼
                         [ GitHub Repository ]
                                  │
               (Secure Outbound HTTPS Polling / Port 443)
                                  │
                                  ▼
              ┌───────────────────────────────────────┐
              │    Target Host / Server               │
              │                                       │
              │  ┌─────────────────────────────────┐  │
              │  │ GitHub Actions Runner (Service) │  │
              │  └────────────────┬────────────────┘  │
              │                   ▼                   │
              │    Trigger Zero-Downtime Script       │
              │          (restart.sh)                 │
              │                   │                   │
              │  1. git reset & pull latest code      │
              │  2. docker compose build (background) │
              │  3. run db migrations (if applicable) │
              │  4. docker compose up -d (fast swap)  │
              │                                       │
              │  ┌─────────────────────────────────┐  │
              │  │ Nginx Reverse Proxy / NPM       │  │
              │  │  • upstream retry on 502/503    │  │
              │  │  • zero client traffic drop     │  │
              │  └─────────────────────────────────┘  │
              └───────────────────────────────────────┘
```

---

## 2. Server-Side Runner Setup

Since you already have the GitHub runner installed as a systemd service (e.g. in `~/actions-runner`), you don't necessarily need a new runner if this project lives on the same server!

If installing on a new server from scratch:
```bash
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64-2.338.2.tar.gz -L https://github.com/actions/runner/releases/download/v2.338.2/actions-runner-linux-x64-2.338.2.tar.gz
tar xzf ./actions-runner-linux-x64-2.338.2.tar.gz

# CRITICAL: Always install dependencies first to avoid Libicu Dotnet Core error
sudo ./bin/installdependencies.sh

# Configure
./config.sh --url https://github.com/<your-org-or-repo> --token <TOKEN>

# Install and start persistent systemd service
sudo ./svc.sh install
sudo ./svc.sh start
```

> [!NOTE]
> If `./config.sh` complains about `Libicu's dependencies is missing for Dotnet Core 6.0`, run `sudo ./bin/installdependencies.sh` and then re-run `./config.sh`. Never skip `./config.sh` and jump to `./run.sh`, otherwise it will error out with `An error occurred: Not configured`.

### How Single-Branch Runner Labeling Works:
1. Go to **GitHub** > **Repository** (or **Organization**) > **Settings** > **Actions** > **Runners**.
2. Click your server runner (e.g., `pa-dev-server` or `smart-sohay-prod-server`).
3. Under **Labels**, ensure it has an identifiable label, for example:
   * **`self-hosted`** (default)
   * A custom label matching your host role (e.g., `production`, `main`, or keep `self-hosted`).

### Server Git SSH Access (Deploy Key Setup)
To ensure the deployment script can run `git pull origin main` without hitting `Permission denied (publickey)`:

1. **Check/Generate SSH Key on Server:**
   ```bash
   cat ~/.ssh/id_ed25519.pub 2>/dev/null || cat ~/.ssh/id_rsa.pub 2>/dev/null
   ```
   If empty, generate one:
   ```bash
   ssh-keygen -t ed25519 -C "server-deploy-key" -N "" -f ~/.ssh/id_ed25519
   cat ~/.ssh/id_ed25519.pub
   ```
2. **Add Deploy Key on GitHub:**
   * Go to repository `Settings` > `Deploy keys` > `Add deploy key`.
   * Title: `production-server`.
   * Paste key, leave write access unchecked, and save.
3. **Switch Remote to SSH:**
   ```bash
   git remote set-url origin git@github.com:<your-org-or-user>/<repo-name>.git
   git pull origin main
   ```

---

## 3. GitHub Actions Workflow (`.github/workflows/deploy.yml`)

Create `.github/workflows/deploy.yml` in the root of your project:

```yaml
name: CI/CD Deployment

on:
  push:
    branches:
      - main
  workflow_dispatch:
    inputs:
      hard_restart:
        description: 'Hard restart (--down: stops containers, removes volumes, and prunes system)?'
        required: false
        default: 'false'
        type: choice
        options:
          - 'false'
          - 'true'

# Prevent concurrent deployments from colliding
concurrency:
  group: deploy-main
  cancel-in-progress: false

jobs:
  deploy:
    name: Deploy to Server
    runs-on: [self-hosted] # or add specific label: [self-hosted, production]
    steps:
      - name: Deploy Main Branch
        working-directory: /home/support/sohay-ielts # Absolute path to project on server
        run: |
          echo "🚀 Starting automated deployment for main branch..."
          if [ "${{ github.event.inputs.hard_restart }}" = "true" ]; then
            bash restart.sh --down
          else
            bash restart.sh
          fi
```

### Explanation of Workflow Settings:
* **`branches: [main]`**: Only triggers when commits are pushed or merged into `main`.
* **`working-directory: /home/support/...`**: Navigates directly into your server's project folder before executing commands.
* **`concurrency: deploy-main`**: Ensures that if 2 pushes happen back-to-back, the second waits in queue rather than building at the exact same moment.

---

## 4. Zero-Downtime `restart.sh` Script

Replace traditional `docker compose down` with background building and seamless container replacement:

```bash
#!/bin/bash
set -e

# ==============================================================================
# Single-Branch (main) Zero-Downtime Deployment & Restart Script
# ==============================================================================
# Usage:
#   sh restart.sh          -> Zero-downtime build, migrate & reload
#   sh restart.sh --down   -> Hard restart (stops containers, removes volumes, full purge)
#   nohup sh restart.sh > restart.log 2>&1 & -> Run in background with logging
# ==============================================================================

echo "📁 Current directory: $(pwd)"

COMPOSE_FILE="docker-compose.yml"
API_SERVICE="api"  # Change to your main web/api container service name in docker-compose.yml

# 1. Reset local changes & pull latest code
echo "🔄 Resetting Git to head..."
git reset --hard

echo "🔄 Pulling latest code from Git (main)..."
git pull origin main

# 2. Check for Hard Restart request
if [ ! -z "$1" ] && [ "$1" = "--down" ]; then
    echo "🛑 [Hard Restart] Stopping and removing containers & volumes..."
    docker compose -f "$COMPOSE_FILE" down --volumes

    echo "🧹 Pruning Docker system..."
    docker system prune -a -f

    echo "🚀 Building and starting containers fresh..."
    docker compose -f "$COMPOSE_FILE" up -d --build
else
    echo "⚡ [Zero-Downtime] Pre-building Docker images in background while traffic is served..."
    docker compose -f "$COMPOSE_FILE" build

    # 3. Database migrations using the newly built image (Optional - e.g., Prisma / Django / Knex)
    echo "🗄️ Checking and running database migrations..."
    # Run migration in a temporary one-off container using the newly built image without taking down traffic
    docker compose -f "$COMPOSE_FILE" run --rm --no-deps "$API_SERVICE" pnpm --filter @sohay/db run migrate:deploy || true

    # 4. Instant container replacement (< 1s switch with zero downtime)
    echo "🚀 Performing seamless container recreation (< 2s switch)..."
    docker compose -f "$COMPOSE_FILE" up -d --no-deps "$API_SERVICE"
    docker compose -f "$COMPOSE_FILE" up -d
fi

echo "✅ Deployment completed successfully."
```

---

## 5. Nginx / Reverse Proxy Configuration (Zero 502 Errors)

To make sure users never experience a `502 Bad Gateway` while the container is switching:

In Nginx Proxy Manager (or Nginx `server` configuration block), add:

```nginx
proxy_buffering off;
proxy_cache off;
chunked_transfer_encoding off;
gzip off;
proxy_read_timeout 3600s;
proxy_send_timeout 3600s;
proxy_next_upstream error timeout http_502 http_503;
proxy_next_upstream_tries 3;
proxy_connect_timeout 5s;
```

---

## 6. How to Deploy

### Automatic Deployment:
Just push or merge into the `main` branch:
```bash
git add .
git commit -m "feat: new feature update"
git push origin main
```

### Manual Trigger from GitHub UI:
1. Go to repository **Actions** tab.
2. Select **CI/CD Deployment** from the left sidebar.
3. Click **Run workflow** ▾.
4. Select `Branch: main` and choose `hard_restart: false` (or `true` if you need a full clean restart).
5. Click the green **Run workflow** button.

---

## 7. How to Skip Deployment on Git Push (`[skip ci]`)

If you want to push commits (e.g. updating documentation, readme, comments) to `main` without triggering an automatic server restart or deployment:

Add **`[skip ci]`** or **`[ci skip]`** into the commit message:

```bash
git add .
git commit -m "docs: update documentation [skip ci]"
git push origin main
```
GitHub Actions will automatically detect this tag and skip the entire deployment job.
