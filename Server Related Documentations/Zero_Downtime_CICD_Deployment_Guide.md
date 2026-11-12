# Zero-Downtime CI/CD Deployment with GitHub Self-Hosted Runner

This documentation provides a comprehensive, production-grade guide for setting up **automated CI/CD pipelines with Zero-Downtime deployments** using **GitHub Self-Hosted Runners** on servers where **SSH (Port 22) is restricted or firewalled**.

---

## Architecture Overview

```
                      [ Git Push: dev or prod branch ]
                                     │
                                     ▼
                            [ GitHub Repository ]
                                     │
                  (Secure Outbound Polling via HTTPS / Port 443)
                                     │
                                     ▼
                 ┌───────────────────────────────────────┐
                 │    Server (Dev or Prod VM)            │
                 │                                       │
                 │  ┌─────────────────────────────────┐  │
                 │  │ GitHub Actions Runner (Service) │  │
                 │  └────────────────┬────────────────┘  │
                 │                   ▼                   │
                 │    Trigger Zero-Downtime Script       │
                 │   (dev_restart.sh / prod_restart.sh)  │
                 │                   │                   │
                 │  1. git reset & pull latest code      │
                 │  2. docker compose build (background) │
                 │  3. python manage.py migrate          │
                 │  4. docker compose up -d (fast swap)  │
                 │                                       │
                 │  ┌─────────────────────────────────┐  │
                 │  │ Nginx Proxy Manager (NPM)       │  │
                 │  │  • upstream retries on 502/503  │  │
                 │  │  • zero client traffic drop     │  │
                 │  └─────────────────────────────────┘  │
                 └───────────────────────────────────────┘
```

---

## Why Self-Hosted Runner? (Overcoming SSH IP Restrictions)

* **Problem:** In security-hardened servers, Port 22 (SSH) is locked down to specific developer IPs. Traditional GitHub Actions cloud runners (`ubuntu-latest`) use dynamic IP pools that cannot enter the firewall without constantly whitelisting IPs.
* **Solution:** A **Self-Hosted Runner** runs inside the server as a systemd service. It creates an **outbound HTTPS connection (Port 443)** to GitHub. No inbound ports (like Port 22) need to be opened to the internet!

---

## Part 1: Setting up GitHub Self-Hosted Runner on Server

You can set up runners at the **Organization level** (shared across all organization repos) or at the **Repository level**.

### Step 1: Download & Configure Runner

1. Go to your GitHub Organization or Repository:
   * **Organization:** `Settings` > `Actions` > `Runners` > `New runner` > Select `Linux` & `x64`.
   * **Repository:** `Settings` > `Actions` > `Runners` > `New self-hosted runner`.
2. SSH into your server and run the installation commands:
   ```bash
   # Create a directory for the runner
   mkdir -p ~/actions-runner && cd ~/actions-runner

   # Download runner package (check GitHub UI for latest version)
   curl -o actions-runner-linux-x64-2.338.2.tar.gz -L https://github.com/actions/runner/releases/download/v2.338.2/actions-runner-linux-x64-2.338.2.tar.gz

   # Extract installer
   tar xzf ./actions-runner-linux-x64-2.338.2.tar.gz

   # Install missing .NET / Libicu dependencies (CRITICAL: prevents Libicu's missing error on Linux)
   sudo ./bin/installdependencies.sh

   # Configure runner with your token
   ./config.sh --url https://github.com/<your-org-or-user> --token <GENERATED_TOKEN>
   ```

> [!IMPORTANT]
> **Dotnet / Libicu Dependency Warning:**
> If you run `./config.sh` before running `installdependencies.sh`, you will encounter this error:
> ```text
> Libicu's dependencies is missing for Dotnet Core 6.0
> Execute sudo ./bin/installdependencies.sh to install any missing Dotnet Core 6.0 dependencies.
> ```
> If this happens, run `sudo ./bin/installdependencies.sh` and then re-execute the `./config.sh ...` command. Do NOT run `./run.sh` before `./config.sh` succeeds, otherwise you will get `An error occurred: Not configured`.

### Step 2: Configure Prompts during `./config.sh`
* **Runner group:** Press `Enter` (default: `Default`).
* **Name of runner:** Enter an identifiable name, e.g., `pa-dev-server` or `smart-sohay-prod-server`.
* **Additional labels:** **CRITICAL!**
  * For Dev server runner: enter **`dev`**
  * For Prod server runner: enter **`prod`**
* **Work folder:** Press `Enter` (default: `_work`).

> [!NOTE]
> If you forgot to add the label during setup, go to `GitHub` > `Settings` > `Actions` > `Runners` > Click your runner > Click `⚙️ Settings` (Labels) > Add `dev` or `prod`.

### Step 3: Run as a Permanent Background Service (Systemd)

Never run `./run.sh` manually for production. Install it as a persistent systemd service:

```bash
sudo ./svc.sh install
sudo ./svc.sh start
```

Verify status:
```bash
sudo ./svc.sh status
```
It should report `Active: active (running)`.

### Step 4: Organization Runner Permissions (If using Org Runner)
If registered under an Organization:
1. Go to `Organization Settings` > `Actions` > `Runner groups` > Click `Default`.
2. Under **Repository access**, ensure `All repositories` is selected (or specifically add your project repository).

---

## Part 2: GitHub Actions Workflow Configuration

Create `.github/workflows/deploy.yml` in your project repository:

```yaml
name: CI/CD Deployment

on:
  push:
    branches:
      - dev
      - prod
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

concurrency:
  group: deploy-${{ github.ref }}
  cancel-in-progress: false

jobs:
  deploy-dev:
    name: Deploy to Dev Server
    if: github.ref == 'refs/heads/dev'
    runs-on: [self-hosted, dev]
    steps:
      - name: Deploy Dev
        working-directory: /home/support/dev-smart-sohay-backend-django
        run: |
          echo "Starting zero-downtime deployment for dev..."
          if [ "${{ github.event.inputs.hard_restart }}" = "true" ]; then
            bash dev_restart.sh --down
          else
            bash dev_restart.sh
          fi

  deploy-prod:
    name: Deploy to Prod Server
    if: github.ref == 'refs/heads/prod'
    runs-on: [self-hosted, prod]
    steps:
      - name: Deploy Prod
        working-directory: /home/support/prod-smart-sohay-backend-django
        run: |
          echo "Starting zero-downtime deployment for prod..."
          if [ "${{ github.event.inputs.hard_restart }}" = "true" ]; then
            bash prod_restart.sh --down
          else
            bash prod_restart.sh
          fi
```

---

## Part 3: Zero-Downtime Deployment Scripts

Traditional `docker compose down` destroys running containers immediately, leaving the website down for 2-3 minutes during the image build and migration phases.

To achieve **Zero Downtime**:
1. Keep old containers running while Docker builds the new image in the background.
2. Run database migrations before swapping containers.
3. Use `docker compose up -d` to swap the running containers instantly (takes < 2 seconds).

### `dev_restart.sh`
```bash
#!/bin/bash
set -e

# Usage:
#   sh dev_restart.sh          -> Zero-downtime build, migrate & reload
#   sh dev_restart.sh --down   -> Hard restart (prune & rebuild from scratch)

echo "📁 Current directory: $(pwd)"

COMPOSE_FILE="docker-compose.dev.yml"
BACKEND_SERVICE="smartsohay_backend_dev"

echo "🔄 Resetting Git to head..."
git reset --hard

echo "🔄 Pulling latest code from Git..."
git pull origin dev

if [ ! -z "$1" ] && [ "$1" = "--down" ]; then
    echo "🛑 [Hard Restart] Stopping and removing containers & volumes..."
    docker compose -f "$COMPOSE_FILE" down --volumes
    docker system prune -a -f
    docker compose -f "$COMPOSE_FILE" up -d --build
else
    echo "⚡ [Zero-Downtime] Pre-building Docker images in background..."
    docker compose -f "$COMPOSE_FILE" build

    echo "📦 Running database migrations..."
    if docker compose -f "$COMPOSE_FILE" ps -q "$BACKEND_SERVICE" | grep -q .; then
        docker compose -f "$COMPOSE_FILE" exec -T "$BACKEND_SERVICE" python manage.py migrate --noinput
    else
        docker compose -f "$COMPOSE_FILE" run --rm --no-deps "$BACKEND_SERVICE" python manage.py migrate --noinput
    fi

    echo "🚀 Performing seamless container recreation..."
    docker compose -f "$COMPOSE_FILE" up -d --no-deps "$BACKEND_SERVICE"
    docker compose -f "$COMPOSE_FILE" up -d
fi

echo "✅ Dev restart complete."
```

### `prod_restart.sh`
```bash
#!/bin/bash
set -e

# Usage:
#   sh prod_restart.sh          -> Zero-downtime build, migrate & reload
#   sh prod_restart.sh --down   -> Hard restart (prune & rebuild from scratch)

echo "📁 Current directory: $(pwd)"

COMPOSE_FILE="docker-compose.prod.yml"
BACKEND_SERVICE="smartsohay_backend_prod"

echo "🔄 Resetting Git to head..."
git reset --hard

echo "🔄 Pulling latest code from Git..."
git pull origin prod

if [ ! -z "$1" ] && [ "$1" = "--down" ]; then
    echo "🛑 [Hard Restart] Stopping and removing containers & volumes..."
    docker compose -f "$COMPOSE_FILE" down --volumes
    docker system prune -a -f
    docker compose -f "$COMPOSE_FILE" up -d --build
else
    echo "⚡ [Zero-Downtime] Pre-building Docker images in background..."
    docker compose -f "$COMPOSE_FILE" build

    echo "📦 Running database migrations..."
    if docker compose -f "$COMPOSE_FILE" ps -q "$BACKEND_SERVICE" | grep -q .; then
        docker compose -f "$COMPOSE_FILE" exec -T "$BACKEND_SERVICE" python manage.py migrate --noinput
    else
        docker compose -f "$COMPOSE_FILE" run --rm --no-deps "$BACKEND_SERVICE" python manage.py migrate --noinput
    fi

    echo "🚀 Performing seamless container recreation..."
    docker compose -f "$COMPOSE_FILE" up -d --no-deps "$BACKEND_SERVICE"
    docker compose -f "$COMPOSE_FILE" up -d
fi

echo "✅ Production restart complete."
```

---

## Part 4: Nginx Proxy Manager (NPM) Zero-Downtime Tuning

Even with instant container replacement, there is a ~1-2 second window where Uvicorn finishes binding to the port. To guarantee clients never see a `502 Bad Gateway`, configure Nginx to buffer and retry requests:

1. Open **Nginx Proxy Manager** (Port 81).
2. Edit your Proxy Host (e.g., `api.smartsohay.com` or `devapi.smartsohay.com`).
3. Under the **Advanced** tab, insert:
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
4. Click **Save**.

### Troubleshooting NPM `Internal Error` on Save:
If saving returns `Internal Error`, it indicates an Nginx syntax or SSL certificate test failure:
* Run inside server:
  ```bash
  docker exec -it <NPM_CONTAINER_NAME> nginx -t
  ```
* If a broken SSL certificate is referenced (e.g. `cannot load certificate ... /npm-11/fullchain.pem`):
  1. Find the culprit config file:
     ```bash
     docker exec -it <NPM_CONTAINER_NAME> grep -rn "npm-11" /data/nginx/
     ```
  2. Backup or remove the invalid host file:
     ```bash
     docker exec -it <NPM_CONTAINER_NAME> mv /data/nginx/proxy_host/11.conf /data/nginx/proxy_host/11.conf.bak
     ```
  3. Reload Nginx:
     ```bash
     docker exec -it <NPM_CONTAINER_NAME> nginx -s reload
     ```

---

## Part 5: Docker & Environment Variables Management

1. **Keep `.env.dev` and `.env.prod` on Server:**
   * Keep `.env*` files inside the server project directory.
   * Because `.env*` is in `.gitignore`, running `git reset --hard` and `git pull` during CI/CD **will never delete or overwrite** your server's local `.env` files.
2. **Internal Network Hardening:**
   * Bind internal database proxies and caches (PgBouncer, Redis) to `127.0.0.1` in `docker-compose.yml`:
     ```yaml
     ports:
       - "127.0.0.1:6432:6432" # PgBouncer
       - "127.0.0.1:6379:6379" # Redis
     ```
   * Containers within the same Docker network continue to communicate securely without exposing ports to the public internet.

---

## Part 6: How to Skip Deployment on Git Push (`[skip ci]`)

Sometimes you may want to push changes to GitHub (e.g. updating documentation, READMEs, helper scripts, or minor comments) **without triggering an automatic server deployment or Docker rebuild**.

GitHub Actions supports built-in commit message keywords to automatically cancel/skip execution.

### How to use:
Simply include **`[skip ci]`** or **`[ci skip]`** anywhere in your commit message:

```bash
git add .
git commit -m "docs: update deployment documentation [skip ci]"
git push origin dev
```

### Supported Keywords:
Any of the following tags will completely bypass the deployment workflow:
* `[skip ci]`
* `[ci skip]`
* `[skip actions]`
* `[actions skip]`

> [!TIP]
> When `[skip ci]` is present, GitHub will show a small neutral/skipped icon next to the commit and will **not execute** any runner jobs on the server.

---

## Summary Checklist for New Projects

- [ ] Install runner in `~/actions-runner` on server.
- [ ] Label runner with environment name (`dev` or `prod`).
- [ ] Install and start runner as a systemd service (`sudo ./svc.sh install && sudo ./svc.sh start`).
- [ ] Add `.github/workflows/deploy.yml` with proper `working-directory`.
- [ ] Use pre-build zero-downtime restart scripts (`dev_restart.sh` / `prod_restart.sh`).
- [ ] Add `proxy_next_upstream` in Nginx Proxy Manager.
- [ ] Push to `dev` or `prod` branch to trigger automatic zero-downtime deployment!
