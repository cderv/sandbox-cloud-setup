# Sandbox facts

Things about the Anthropic-hosted cloud VM that this setup relies on, or
that were useful to know. The platform changes; each fact says how it was
established. **Docs** = [Configure cloud environments](https://code.claude.com/docs/en/cloud-environments)
or [Use Claude Code in the cloud](https://code.claude.com/docs/en/claude-code-on-the-web);
**seen** = observed in a session, with the date.

## Setup script and cache

| Fact | Source |
|---|---|
| The setup script runs as root on Ubuntu 24.04, before Claude Code starts. | Docs |
| It **does not see the environment's variables** (they are set after it). | Docs ("The environment's variables aren't set yet") |
| A non-zero exit fails the session start. | Docs |
| It must finish in about 5 minutes to be cached. | Docs |
| The filesystem is snapshotted and reused by later sessions. It is rebuilt when the script or the network settings change, or after about 7 days. | Docs |
| Each new session starts from the snapshot: what a session installs is lost for the next one. | Docs ("The cache is a filesystem snapshot") |
| Requests made by the setup script don't get network secrets. | Docs |
| Environment variables are re-read when Claude Code starts in the VM (new session, VM restored after idle, VM rebuilt). | Docs |

## The VM

| Fact | Source |
|---|---|
| `HOME=/root`; `~/.local/bin` is on `PATH`. | Seen 2026-11-04 |
| `CLAUDE_CODE_REMOTE=true` in sessions (use it to scope hooks to the cloud). | Docs, seen 2026-11-04 |
| About 4 vCPUs, 16 GB RAM, 30 GB disk. | Docs |
| Node 22 is the default `node` (`/opt/node22/bin`); `/opt/node24` also exists. npm 10.9. | Seen 2026-11-04 |
| `gh` is pre-installed (`/usr/local/bin/gh`, 2.89.0). | Seen 2026-11-04 |
| Playwright Chromium is pre-installed: `/opt/pw-browsers/chromium` (a symlink to `chromium-<rev>/chrome-linux64/chrome`). Use that path for any tool that needs Chrome. | Seen 2026-11-04 |
| User-level `~/.claude/settings.json` hooks and `~/.claude/skills/` written in the VM are loaded (this setup relies on it). Your *laptop's* `~/.claude` does not reach the cloud. | Docs, seen |
| A SessionStart command hook is cancelled after 600 s unless `timeout` is set (this repo sets 300). | Docs |

## Network

| Fact | Source |
|---|---|
| All outbound traffic goes through an HTTPS proxy that re-signs TLS. Its CA bundle is `/root/.ccr/ca-bundle.crt`; `curl -sS "$HTTPS_PROXY/__agentproxy/status"` shows its state. | Seen 2026-11-04 |
| Chromium trusts the proxy because the platform puts its CA in `/root/.pki/nssdb` at session start. | Seen 2026-11-04 |
| Package registries (`registry.npmjs.org`, `pypi.org`, ...) are in `NO_PROXY`. | Seen 2026-11-04 |
| Under **Trusted**, hosts outside the allowlist are refused by the proxy (403 on CONNECT): `example.com`, `agent-browser.dev`, `googlechromelabs.github.io`, `quarto.org`, `just.systems` (seen 2026-11-05), and every host R needs (`api.r-hub.io`, `cdn.posit.co`, `r-lib.github.io`, `packagemanager.posit.co`, `cloud.r-project.org`) were. `github.com` (git and release downloads, but not HTML pages such as `/releases/latest`, which get a 403) and `raw.githubusercontent.com` are reachable. | Seen 2026-11-04 |
| GitHub goes through a separate GitHub proxy: API calls only for attached repositories, no GraphQL, no tag pushes. See [GitHub](github.md). | Docs |

## Environments and sessions

| Fact | Source |
|---|---|
| No API or CLI creates or edits an environment. `/remote-env` only picks the CLI default. | Docs, checked 2026-11-04 |
| Onboarding's **Default** environment has no setup script and no variables. | Docs |
| A session can list your environments (read only). | Seen 2026-11-04 |
| Cloud sessions pick their own branch name (`claude/<words>-<suffix>`); there is no documented setting for it. | Docs, checked 2026-11-04 |
| Plugins enabled in a repo's `.claude/settings.json` are not installed in cloud sessions; hooks, skills, agents and `.mcp.json` from a repo are (single-repo sessions only). | Docs |
