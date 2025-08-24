#!/usr/bin/env bash
# install_docker.sh
# Purpose: Clean conflicting packages, add Docker's official repo, and install Docker CE stack on Ubuntu.
# Usage: chmod +x install_docker.sh && ./install_docker.sh
# Notes:
# - Safe to re-run (idempotent-ish). Absent packages are ignored.
# - After running, you may need to log out/in for the docker group to take effect.
# - The final `newgrp docker` only affects the current shell session.

set -euo pipefail

# Ensure we are on Ubuntu
if ! [ -f /etc/os-release ]; then
  echo "This script is intended for Ubuntu (Debian-based). /etc/os-release not found." >&2
  exit 1
fi

# Make apt noninteractive to avoid prompts
export DEBIAN_FRONTEND=noninteractive

echo "==> Removing conflicting Docker/Container runtimes (if present) ..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    sudo apt-get -y remove "$pkg" || true
  fi
done

echo "==> Installing prerequisites ..."
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release

echo "==> Setting up Docker's official GPG key ..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "==> Adding Docker APT repository ..."
UBUNTU_CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
ARCH="$(dpkg --print-architecture)"
echo "Using codename: ${UBUNTU_CODENAME}, arch: ${ARCH}"

# Write the repo file (idempotent)
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

echo "==> Updating apt cache ..."
sudo apt-get update -y

echo "==> Installing Docker CE, CLI, containerd, Buildx, and Compose plugin ..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "==> Ensuring 'docker' group exists and adding current user ..."
if ! getent group docker >/dev/null 2>&1; then
  sudo groupadd docker
fi
sudo usermod -aG docker "$USER" || true

# Try to activate group for current shell if running non-root
if [ "${SUDO_USER:-}" != "" ]; then
  echo "==> You ran with sudo; adding SUDO_USER (${SUDO_USER}) to docker group too ..."
  sudo usermod -aG docker "$SUDO_USER" || true
fi

# Start/enable services
echo "==> Enabling and starting Docker service ..."
sudo systemctl enable --now docker

echo "==> Verifying Docker installation ..."
docker --version || true
docker compose version || true

echo
echo "✅ Docker installation steps complete."
echo "➡  To use docker without sudo, log out and log back in (or run: newgrp docker)."
