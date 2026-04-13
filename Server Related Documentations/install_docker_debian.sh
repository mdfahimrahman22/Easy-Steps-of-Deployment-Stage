#!/usr/bin/env bash
# install_docker_debian.sh
# Purpose: Clean conflicting packages, add Docker's official repo, and install Docker CE stack on Debian.
# Usage: chmod +x install_docker_debian.sh && ./install_docker_debian.sh
# Notes:
# - Safe to re-run (idempotent-ish). Absent packages are ignored.
# - Run as your normal user (not root). The script uses sudo internally where needed.
# - The script activates the docker group for the current shell via `newgrp docker`.
# - For all future SSH sessions the group will be active automatically (no logout needed).

set -euo pipefail

# Ensure we are on Debian
if ! [ -f /etc/os-release ]; then
  echo "This script is intended for Debian. /etc/os-release not found." >&2
  exit 1
fi

DETECTED_ID="$(. /etc/os-release && echo "${ID}")"
if [ "${DETECTED_ID}" != "debian" ]; then
  echo "This script is intended for Debian only. Detected OS: ${DETECTED_ID}" >&2
  exit 1
fi

# Make apt noninteractive to avoid prompts
export DEBIAN_FRONTEND=noninteractive

echo "==> Removing any stale Docker APT repository configuration ..."
# A previous failed run (e.g. with the Ubuntu URL) may have left a broken
# /etc/apt/sources.list.d/docker.list. Remove it now so the first
# apt-get update (for prerequisites) does not fail.
sudo rm -f /etc/apt/sources.list.d/docker.list

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
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "==> Adding Docker APT repository ..."
# On Debian, VERSION_CODENAME always holds the correct codename (e.g. bookworm, bullseye, buster).
# UBUNTU_CODENAME does NOT exist on Debian, so we use VERSION_CODENAME directly.
DEBIAN_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
ARCH="$(dpkg --print-architecture)"
echo "Using codename: ${DEBIAN_CODENAME}, arch: ${ARCH}"

# Write the repo file (idempotent)
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${DEBIAN_CODENAME} stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

echo "==> Updating apt cache ..."
sudo apt-get update -y

echo "==> Installing Docker CE, CLI, containerd, Buildx, and Compose plugin ..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "==> Ensuring 'docker' group exists and adding current user ..."
if ! getent group docker >/dev/null 2>&1; then
  sudo groupadd docker
fi

# Determine the real (non-root) user to add to the docker group.
# When the script is invoked with sudo, $USER becomes 'root'.
# SUDO_USER holds the original caller's username in that case.
REAL_USER="${SUDO_USER:-$USER}"
echo "Adding '${REAL_USER}' to the docker group ..."
sudo usermod -aG docker "${REAL_USER}"

# Start/enable services
echo "==> Enabling and starting Docker service ..."
sudo systemctl enable --now docker

echo "==> Verifying Docker installation ..."
docker --version || true
docker compose version || true

echo
echo "✅ Docker installation steps complete."
echo "➡  Activating docker group for the current shell session (no logout required) ..."
echo "   For all future SSH sessions it will be active automatically."

# Activate the docker group in the current shell so `docker ps` works immediately
# without requiring a logout/login. This replaces the current shell with a new one
# that has the updated group membership.
exec newgrp docker
