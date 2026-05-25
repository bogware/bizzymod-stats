#!/usr/bin/env bash
# Idempotent setup script for a self-hosted bizzymod-stats CI runner.
# Run once after registering the runner with GitHub.
#
# Usage:  sudo bash runner-setup.sh
#
# This script:
#   - Installs docker, python3, zip/unzip/tar, curl, git
#   - Adds the invoking user to the docker group
#   - (Optionally) pre-installs the SourceMod 1.12 toolchain at /opt/sourcemod-1.12
#
# It does NOT register the runner itself — follow docs/CI.md for that.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root (sudo bash runner-setup.sh)" >&2
    exit 1
fi

TARGET_USER="${SUDO_USER:-runner}"
echo "Setting up runner prerequisites for user: $TARGET_USER"

# ------------------------------------------------------------------
# 1. apt prerequisites
# ------------------------------------------------------------------
echo "==> apt prerequisites"
apt-get update -y
apt-get install -y \
    curl unzip tar zip git ca-certificates \
    python3 python3-pip \
    docker.io

# ------------------------------------------------------------------
# 2. docker group membership
# ------------------------------------------------------------------
echo "==> adding $TARGET_USER to docker group"
usermod -aG docker "$TARGET_USER" || true

systemctl enable --now docker

# ------------------------------------------------------------------
# 3. SourceMod 1.12 toolchain (optional but recommended)
# ------------------------------------------------------------------
SM_DIR="/opt/sourcemod-1.12"
if [[ ! -x "$SM_DIR/addons/sourcemod/scripting/spcomp" ]]; then
    echo "==> installing SourceMod 1.12 toolchain to $SM_DIR"
    mkdir -p "$SM_DIR"
    curl -sLo "$SM_DIR/sm.tar.gz" \
        https://sm.alliedmods.net/smdrop/1.12/sourcemod-1.12.0-git7210-linux.tar.gz
    tar xzf "$SM_DIR/sm.tar.gz" -C "$SM_DIR"
    rm -f "$SM_DIR/sm.tar.gz"
    chmod +x "$SM_DIR/addons/sourcemod/scripting/spcomp" 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 4. Persist toolchain env for the runner
# ------------------------------------------------------------------
RUNNER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
RUNNER_ENV="$RUNNER_HOME/actions-runner/.env"
if [[ -d "$RUNNER_HOME/actions-runner" ]]; then
    echo "==> writing $RUNNER_ENV"
    {
        echo "SPCOMP=$SM_DIR/addons/sourcemod/scripting/spcomp"
        echo "SM_INCLUDE=$SM_DIR/addons/sourcemod/scripting/include"
    } > "$RUNNER_ENV"
    chown "$TARGET_USER" "$RUNNER_ENV"
else
    echo "==> actions-runner not yet installed at $RUNNER_HOME/actions-runner"
    echo "    Register your runner first; then re-run this script to wire up env."
fi

# ------------------------------------------------------------------
# 5. pip prereqs
# ------------------------------------------------------------------
echo "==> pymysql for python3"
sudo -u "$TARGET_USER" python3 -m pip install --user --quiet pymysql

echo
echo "Setup complete. Next:"
echo "  - log out and back in (docker group)"
echo "  - if not yet done, register the runner:  see docs/CI.md"
echo "  - start the runner service:              cd ~/actions-runner && sudo ./svc.sh start"
