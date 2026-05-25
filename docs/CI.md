# CI/CD — self-hosted runner setup

`bizzymod-stats` runs CI and tagged releases on a **self-hosted GitHub
Actions runner** so we control the toolchain (SourceMod 1.12 spcomp,
MySQL container, Python). This doc covers what the runner needs.

## TL;DR

On a Linux box you control (Ubuntu 22.04+ recommended):

```bash
# 1) Install prerequisites
sudo apt update
sudo apt install -y curl unzip tar zip git ca-certificates \
    python3 python3-pip docker.io
sudo usermod -aG docker "$USER"  # log out/in after this

# 2) Register the runner against the bizzymod-stats repo
# Go to:  https://github.com/<you>/bizzymod-stats/settings/actions/runners/new
# Copy the snippet that GitHub gives you (it includes a one-time token):
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner.tar.gz -L \
   https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64.tar.gz
tar xzf actions-runner.tar.gz
./config.sh --url https://github.com/<you>/bizzymod-stats --token <TOKEN-FROM-GITHUB>
# Accept the default work folder and labels.

# 3) Run as a systemd service so it survives reboots
sudo ./svc.sh install
sudo ./svc.sh start

# 4) Sanity check
./run.sh --check
```

The runner needs the `self-hosted` label (added by GitHub
automatically) and the `linux` label (also automatic). No custom labels
needed beyond those — our workflows target `runs-on: [self-hosted, linux]`.

## Self-healing prereqs

The workflows run `.github/ensure-prereqs.sh` as their first step. If
any of {`docker`, `curl`, `unzip`, `tar`, `zip`, `git`, `python3`} is
missing, the script attempts to install it via `sudo -n apt-get` (i.e.
non-interactive passwordless sudo). This means a fresh runner only has
to be **registered** — the workflow installs everything else on demand.

For the auto-install to work, the runner user needs **passwordless sudo
for `apt-get`**. Add this once to `/etc/sudoers.d/bizzymod-runner`:

```bash
sudo visudo -f /etc/sudoers.d/bizzymod-runner
```

```
# Allow the actions-runner user to install packages without a prompt
<runner-user> ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt
```

(Replace `<runner-user>` with whatever user owns `~/actions-runner`.)

If passwordless sudo isn't configured, the workflow fails with a clear
message telling you what's missing — at which point you can either run
`sudo bash .github/runner-setup.sh` once on the host, or grant sudo and
re-trigger.

A docker install also requires the runner user to be in the `docker`
group. The ensure-prereqs script warns if `docker ps` fails after a
fresh install; in that case run `sudo usermod -aG docker $USER &&
sudo systemctl restart actions.runner.*` once.

## What the workflows expect on the runner

| Requirement | Version       | Used by                          | Install command |
|-------------|---------------|----------------------------------|-----------------|
| `bash`      | any modern    | `tests/run.sh` orchestration     | preinstalled    |
| `docker`    | 20.10+        | MySQL test container             | `apt install docker.io` |
| `curl`      | any           | toolchain download fallback      | `apt install curl` |
| `unzip`     | any           | SourceMod zip extraction         | `apt install unzip` |
| `tar`       | any           | SourceMod tarball extraction     | `apt install tar` |
| `zip`       | any           | release packaging                | `apt install zip` |
| `python3`   | 3.10+         | migrations runner                | `apt install python3 python3-pip` |
| `pip` pkg `pymysql` | 1.1+  | migrations runner                | the workflow installs this |
| `git`       | any           | checkout + changelog             | `apt install git` |

The SourceMod 1.12 toolchain (spcomp + standard includes) is **auto-downloaded**
to `tests/.sm-toolchain/` on first run. If you want to skip the download
on every CI run, pre-install it once and set the env on the runner:

```bash
mkdir -p /opt/sourcemod-1.12
cd /opt/sourcemod-1.12
curl -sLO https://sm.alliedmods.net/smdrop/1.12/sourcemod-1.12.0-git7210-linux.tar.gz
tar xzf sourcemod-1.12.0-git7210-linux.tar.gz
# Then on the runner, set persistent environment variables:
# (~/actions-runner/.env)
echo 'SPCOMP=/opt/sourcemod-1.12/addons/sourcemod/scripting/spcomp' >> ~/actions-runner/.env
echo 'SM_INCLUDE=/opt/sourcemod-1.12/addons/sourcemod/scripting/include' >> ~/actions-runner/.env
sudo systemctl restart actions.runner.<repo>.<name>.service
```

## Concurrency and ports

The test harness starts a MySQL container on port `33399` (overridable via
`BIZZY_TEST_MYSQL_PORT`). If two workflows run concurrently they'll
collide; either:

- Limit the runner to one concurrent job (`./config.sh --runnergroup ...`)
- Or set `concurrency:` on the workflows (already implicit per-branch for
  PR/push; release runs once per tag).

We default to one-job-at-a-time by relying on GitHub's per-workflow
concurrency model and the unique container name `bizzy-mysql-tests`.

## Release tokens

`.github/workflows/release.yml` uses the default `GITHUB_TOKEN` provided
to every workflow run. No extra secrets needed for our release flow.
If you fork and rename the repo, the workflow continues to work — it
infers the repo from the workflow context.

## Verifying the runner works

After registration, push a tiny commit (or trigger via the **Actions**
tab → Run workflow). The first `tests` job should:

1. Verify prerequisites (fast)
2. Install pymysql for the current user (~5s the first time, cached after)
3. Run `tests/run.sh` (~60-90s end-to-end on first run due to
   toolchain download; ~30-45s on subsequent runs)
4. Upload the compiled `.smx` as an artifact

If any step fails, the runner's log will show the same output you'd see
running `tests/run.sh` locally — there's no CI magic on top of it.

## Releasing

```bash
git tag -a v2.0.0 -m "bizzymod-stats 2.0.0"
git push origin v2.0.0
```

The `release` workflow then runs the same `tests/run.sh` as a gate,
stages a release tree, zips it, generates a `git log`-based changelog,
and publishes to a GitHub Release with the zip attached.

Versions containing a hyphen (e.g. `v2.0.0-rc1`) are automatically
marked as pre-releases.

## Troubleshooting

**"docker: permission denied"** — the runner's user isn't in the `docker`
group. `sudo usermod -aG docker <runner-user>` then restart the runner
service.

**"Python was not found; run without arguments…"** — Windows runner with
the Microsoft Store python stub. Either install a real python from
python.org or set `command -v python` to point to a real interpreter.
The test script prefers a working interpreter via `--version` probe.

**Toolchain download fails** — `sm.alliedmods.net` may be slow from your
region. Set the `SPCOMP=` and `SM_INCLUDE=` env vars to a pre-installed
toolchain (see above).

**MySQL port in use** — set `BIZZY_TEST_MYSQL_PORT=33500` (or anything
free) as a repository-level secret or runner env var.

## Multiple runners

If you operate 4-8 servers as the spec suggests, you may also be the
person who runs the runner. Recommended: one beefy runner box (4 vCPU,
4GB RAM) — the test harness is docker-heavy. CI runs are infrequent
enough that one runner is fine; double up only if release windows
overlap PR validation.
