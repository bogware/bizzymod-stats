#!/usr/bin/env bash
# Idempotent CI prereq check used by .github/workflows/{ci,release}.yml.
#
# For each required tool that isn't on PATH, attempts `sudo -n apt-get install`
# (passwordless apt). If sudo isn't available or apt-get fails, prints a
# helpful message pointing at .github/runner-setup.sh and exits non-zero.
#
# Tools probed:
#   bash docker curl unzip tar zip git python3
#
# The Python check uses --version because Windows runners with the Microsoft
# Store stub have python3 on PATH but it isn't a real interpreter.

set -euo pipefail

REQUIRED_BINS=(docker curl unzip tar zip git)

missing=()
for cmd in "${REQUIRED_BINS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing+=("$cmd")
    fi
done

# Python: probe a working interpreter rather than relying on `command -v`.
have_python=0
for c in python3 python python3.12 python3.11 python3.10; do
    if command -v "$c" >/dev/null 2>&1 \
       && "$c" -c "import sys" >/dev/null 2>&1; then
        have_python=1
        break
    fi
done
if [[ $have_python -eq 0 ]]; then
    missing+=("python3")
fi

if [[ ${#missing[@]} -eq 0 ]]; then
    echo "All prerequisites present: ${REQUIRED_BINS[*]} + python3."
    exit 0
fi

echo "Missing prerequisites on this runner: ${missing[*]}"

# Map the binary name to the apt package (mostly identical, but python3
# needs python3-pip too for the workflow's pip install step).
declare -A APT_PKGS=(
    [docker]="docker.io"
    [curl]="curl"
    [unzip]="unzip"
    [tar]="tar"
    [zip]="zip"
    [git]="git"
    [python3]="python3 python3-pip"
)

pkgs=()
for bin in "${missing[@]}"; do
    pkgs+=(${APT_PKGS[$bin]:-$bin})
done

# Try passwordless sudo apt-get. If sudo isn't available or apt-get isn't,
# print the runner-setup.sh hint and bail.
if ! command -v apt-get >/dev/null 2>&1; then
    cat >&2 <<EOF
ERROR: apt-get not available on this runner.

This CI workflow expects a Debian/Ubuntu-flavoured runner. To register a
runner that satisfies the prereqs in one shot, run:

    sudo bash .github/runner-setup.sh

on the runner host before retrying the workflow.
EOF
    exit 1
fi

if ! sudo -n true 2>/dev/null; then
    cat >&2 <<EOF
ERROR: passwordless sudo not configured for this runner.

To let CI auto-install missing prerequisites, add to /etc/sudoers.d/runner:

    <runner-user> ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt

Or pre-install once with:

    sudo bash .github/runner-setup.sh

Missing: ${missing[*]}
EOF
    exit 1
fi

echo "Installing: ${pkgs[*]}"
sudo -n apt-get update -y -qq
sudo -n DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${pkgs[@]}"

# If we just installed docker, the runner may not be in the docker group
# yet — but the running CI process already cached its group set at login,
# so a fresh `docker ps` may fail with permission denied. The runner-setup
# script handles this for fresh installs; on the fly we just try the
# default group and warn.
if [[ " ${missing[*]} " == *" docker "* ]]; then
    if ! docker ps >/dev/null 2>&1; then
        echo "WARNING: docker installed but the runner user can't reach the daemon yet."
        echo "         Add the user to the docker group and restart the runner service:"
        echo "             sudo usermod -aG docker \$USER && sudo systemctl restart actions.runner.*"
    fi
fi

# Re-verify
still_missing=()
for cmd in "${REQUIRED_BINS[@]}"; do
    command -v "$cmd" >/dev/null 2>&1 || still_missing+=("$cmd")
done
have_python=0
for c in python3 python python3.12 python3.11 python3.10; do
    if command -v "$c" >/dev/null 2>&1 \
       && "$c" -c "import sys" >/dev/null 2>&1; then
        have_python=1; break
    fi
done
[[ $have_python -eq 0 ]] && still_missing+=("python3")

if [[ ${#still_missing[@]} -gt 0 ]]; then
    echo "ERROR: still missing after install attempt: ${still_missing[*]}" >&2
    exit 1
fi

echo "All prerequisites now present."
