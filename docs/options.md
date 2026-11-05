# Options (opt-in features)

| Option | Values | Effect |
|---|---|---|
| `CLOUD_SETUP_BRAID` | an exact version (`0.8.1`) | Installs [braid](https://github.com/cscheid/braid) (automerge sync client) with its signed, checksum-verified installer, into `~/.local/bin/braid`. When on, sessions warn if `BRAID_SYNC_URL` is unset (braid would use the public relay). Keep every peer (laptop, cloud) on the same version. |
| `CLOUD_SETUP_QUARTO` | `release`, `prerelease`, or an exact version (`1.11.9`) | Installs Quarto from its GitHub release into `/opt/quarto/<version>`, linked as `~/.local/bin/quarto`. `release` and `prerelease` resolve the current version when setup runs (from the quarto-web repo on GitHub, since quarto.org is not on the Trusted allowlist). |
| `CLOUD_SETUP_R` | `release` or an exact version (`4.5.2`) | Installs [rig](https://github.com/r-lib/rig) (pinned in `setup.sh`, into `/usr/local`), then `rig add <version>`: Posit's R build for Ubuntu 24.04 in `/opt/R/<version>`, made the default and linked as `/usr/local/bin/R` and `Rscript`. rig also sets up the Posit Package Manager binary repository (fast `install.packages()`) and installs pak. `release` resolves the current version (`rig resolve`) when setup runs. Other rig specs (`4.5`, `oldrel`) work too, but are only checked for "some R is installed". **Needs Custom network access** (see [R notes](#r-notes)). |
| `CLOUD_SETUP_UV` | `latest` or an exact version (`0.13.7`) | Installs `uv` and `uvx` from their GitHub release into `~/.local/bin`, replacing the copy the image may ship (it can lag behind). `latest` resolves the newest stable tag when setup runs. Empty: the image's uv, if any, is left alone. |
| `CLOUD_SETUP_PYTHON` | one or more versions, space- or comma-separated (`3.12`, `3.12 3.14`, `3.12.13`) | Runs `uv python install <versions>`: uv-managed CPython in `~/.local/share/uv/python`, linked as `~/.local/bin/python3.X`. If no uv exists at all, installs the latest one first. |
| `CLOUD_SETUP_AGENT_BROWSER` | `latest`, or an exact version (`0.41.2`) | Installs [agent-browser](agent-browser.md) and its Claude Code skill, set up to use the image's Chromium. |
| `CLOUD_SETUP_ATTRIBUTION` | `keep` | By default setup writes `"attribution": {"commit": "", "pr": "", "sessionUrl": false}` to `~/.claude/settings.json`, so commits and PRs carry no Co-Authored-By trailer, no `Claude-Session:` link and no PR-body session link. `keep` leaves Claude Code's default attribution. |
| `CLOUD_SETUP_SECRET_VARS` | variable names, comma-separated (`MY_API_KEY,OTHER_TOKEN`) | Extra environment variables the [secret guard](secret-guard.md) keeps out of Claude's context, on top of `BRAID_DOC_ID`. **Names only, never values.** |
| `CLOUD_SETUP_REF` | branch, tag or full 40-char SHA | Which commit of the repo to follow. In the block it is `PIN`; as a variable it wins over `PIN`. See [pinning](how-it-works.md#pinning-and-the-trust-model). |
| `CLOUD_SETUP_REPO` | git URL | Which repo to follow. In the block it is `REPO` (set it to your fork's URL); as a variable it wins over `REPO`. Anyone who can edit the environment can point it elsewhere, and it runs as root: same trust as `CLOUD_SETUP_REF`. |

Empty means off. An option takes effect at the next **new** session.
Turning an option off later does not uninstall anything; it only stops the
checks. Changing a version keeps the older ones on disk (Quarto, R), so
switching back is fast.

## Two places to set an option

| Where | When it is installed | Use it for |
|---|---|---|
| **Options block at the top of the pasted `bootstrap.sh`** (recommended) | Once, by the setup script. The result is part of the cached image, so every session starts with it. Editing the block rebuilds the cache. | What you want in this environment for good, especially heavy downloads like Quarto. |
| **Environment variable** of the same name | By the session-start hook, at **every new session**: a variable change does not rebuild the cache, and what a session installs is not saved back to it. | Trying an option out, or overriding the block in one environment. |

A variable wins over the block. `off` turns off what the block turned on, for
example `CLOUD_SETUP_QUARTO=off`.

**Why two places.** The setup script runs *before* the environment's
variables are set, so it cannot read them
([docs](https://code.claude.com/docs/en/cloud-environments#script-requirements)).
Only the session-start hook sees the variables. Earlier versions of this
repo read options only from variables, so they were always installed by the
hook, at every session.

`setup.sh`, `session-start.sh` and `cloud-doctor` resolve an option the same
way: the variable `CLOUD_SETUP_<NAME>` when set, otherwise its line in
`~/.config/cloud-setup/defaults` (written by `bootstrap.sh` from its block),
`off` meaning empty. `cloud-doctor` shows where each value came from.

An environment set up with an older `bootstrap.sh` (no options block) keeps
working: options then come from variables only. Re-paste the current
`bootstrap.sh` to get the block.

**braid used to be installed in every environment.** It is now an option:
an environment that uses it needs `CLOUD_SETUP_BRAID="0.8.1"` in its block
(or as a variable). Without it, sessions stop checking braid, and braid
disappears at the next image rebuild. See [Updating an environment](migration.md).

## R notes

- **Network: R needs Custom network access.** None of its hosts are on the
  Trusted list (checked 2026-11-05): add `api.r-hub.io` (rig resolving a
  version), `cdn.posit.co` (the R build), `r-lib.github.io` (pak), and for
  packages `packagemanager.posit.co` and `cloud.r-project.org`. The Ubuntu
  apt mirrors R's system dependencies come from are on the Trusted list.
  Under Trusted, setup reports "could not resolve" and skips R.
- Project packages don't belong here: keep them in the project (renv or
  `DESCRIPTION`), installed from the Posit binaries in seconds.
- `R` and `Rscript` come from `/usr/local/bin`; switching `CLOUD_SETUP_R` to
  an installed version only changes rig's default.

## Python notes

- setup never runs `uv python install --default`, which would put
  `python`/`python3` in `~/.local/bin`, ahead of the system interpreter the
  hooks run with. So `python3` stays the image's, and the extra versions are
  `python3.12`, `python3.14`, ...
- Projects choose one with `.python-version` / `requires-python` or
  `uv run -p 3.12`. uv downloads a missing version on demand anyway (a few
  seconds): `CLOUD_SETUP_PYTHON` only puts it in the cached image ahead of
  time.
- uv and Python come from GitHub releases: Trusted is enough.

## Install times

Measured in a container: a few seconds for Quarto, uv, a Python version or
agent-browser, about 30 s for R (13 s for a second R version). With the
options block this is paid once, when the image is built. Set as a variable,
it is paid at each new session (the session-start hook allows `setup.sh` 4
minutes).

## Adding an option

1. In `setup.sh`: read it with `X_WANT="$(opt X)"`, install it non-fatally
   (`|| echo "... skipped"`), skip when it is already at the wanted version,
   and record `x=$X_WANT` in the state file.
2. Add `CLOUD_SETUP_X=""` to the options block **and** to the `defaults`
   file it writes, in `bootstrap.sh`.
3. In `session-start.sh`: compare it in `features_ok` and add it to the
   healthy line.
4. In `cloud-doctor.py`: add it to the feature loop.
5. Document it in the table above, with the network hosts it needs, and add
   a CI job in `.github/workflows/test.yml` that installs it twice (the
   second run must be a no-op).
