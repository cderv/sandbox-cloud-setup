# sandbox-cloud-setup

A reproducible setup for Claude Code on the web (claude.ai/code)
environments. It installs extra tools and adds a **secret guard** that keeps
environment secrets (e.g. `BRAID_DOC_ID`) out of Claude's context.

This repo is **public on purpose**: it holds no secrets, so the setup script
can fetch it without a token. Secret *values* live only in the environment
settings on claude.ai (see [Keeping it public](#keeping-it-public)).

| File | Role |
|---|---|
| `bootstrap.sh` | The only thing pasted into claude.ai, **once, never edited**. Fetches this repo (`main`, or `CLOUD_SETUP_REF`) and runs `setup.sh`. |
| `setup.sh` | Installs `gh` if the image lacks it, plus extra tools (braid) and the [opt-in features](#opt-in-features) the environment's variables ask for (Quarto, R, uv, Python), registers the hooks, records what it installed. |
| `session-start.sh` | SessionStart hook: brings the environment to `CLOUD_SETUP_REF` (default `main`) at each new session, installs a newly requested opt-in feature, repairs a missing tool, warns when something is off. |
| `secret-guard.py` | A Claude Code hook: blocks commands that would print secrets and redacts secrets from tool output. |
| `cloud-doctor.py` | Installed as `~/.local/bin/cloud-doctor`. Checks the setup (hooks, tools, opt-in features, GitHub access) and prints no secrets. |
| `test_secret_guard.py` | Offline tests for the guard, also run in CI. |

## GitHub in the sandbox: no token needed (or possible)

In Anthropic-hosted environments, **every GitHub request goes through the
platform's GitHub proxy**, whatever the network access level. From the
[docs](https://code.claude.com/docs/en/cloud-environments#github-proxy):

- **The proxy authenticates for you.** Leave `GH_TOKEN` unset. It then reads
  as the placeholder `proxy-injected`, and `gh`/git just work.
- **Only attached repositories are reachable.** API calls reach only repos
  attached to the session: pick them when starting the session, or ask Claude
  to attach one. A token you set yourself doesn't widen this, it only sits
  readable in the environment. So don't set `GH_TOKEN`.
- **GraphQL is limited to a fixed set of PR operations.** `gh issue list`,
  `gh pr view` and similar commands fail. Use REST:
  `gh api repos/OWNER/REPO/issues`.
- **Public repos you can't attach** (upstream of a fork): `git clone`/`fetch`
  works. To read an issue, give Claude its URL; Claude's web fetch runs
  outside the sandbox. To read many issues in structured form, a GitHub MCP
  connector (claude.ai → Customize → Connectors) is the heavier alternative.

**Contributing to someone else's repo:** start the session on your fork, add
`upstream` as a git remote, hand Claude the issue URL, and open the PR from
your fork on GitHub.

## How claude.ai/code runs it

```
1. SETUP SCRIPT (root, before Claude Code starts, result CACHED)
   bootstrap.sh
     ├─ reads PIN / CLOUD_SETUP_REF  → which commit/tag/branch of this repo
     ├─ fetches that version into /opt/sandbox-cloud-setup (public, no token)
     └─ runs setup.sh
          ├─ gh (only if missing) → ~/.local/bin/gh
          ├─ extra tools          → braid (pinned)
          ├─ opt-in features      → Quarto, R (rig), uv, Python (uv): only those
          │                           whose CLOUD_SETUP_* variable is set
          ├─ secret-guard.py + session-start.sh → ~/.claude/hooks/, registered in ~/.claude/settings.json
          └─ ~/.config/cloud-setup/state  (rev= installed commit, braid= expected
                                           version, quarto= r= uv= python= attribution=
                                           the variables it ran with)

2. EVERY NEW OR RESUMED SESSION (SessionStart hook, NOT cached)
   session-start.sh
     ├─ fetches this repo at CLOUD_SETUP_REF (default main)
     ├─ that commit != rev= ?  → re-runs its setup.sh (idempotent)
     ├─ a tool missing / wrong version, or a CLOUD_SETUP_* variable
     │  different from the state file ? → re-runs setup.sh once (repair)
     └─ reports: one line to Claude when healthy, a warning to you otherwise

3. EVERY TOOL CALL
   PreToolUse  → deny commands that would print a secret (env dump, set -x,
                 echo $BRAID_DOC_ID, braid secret, curl -v, ...)
   PostToolUse → if a secret value or a GitHub token pattern appears in the
                 output, Claude gets a redacted copy instead
```

### The cache: when does setup.sh actually run?

claude.ai/code **saves the container state produced by the setup script and
reuses it** for later sessions. The setup script re-runs, and the cache is
rebuilt, only when:

- the **setup script text is edited**,
- the environment's **network settings change**, or
- the cache is about **7 days** old.

Changing an environment **variable** is not listed as a trigger, and neither
is a **push to this repo**. That is why updates don't rely on the cache:
`session-start.sh` runs at every new or resumed session, fetches the wanted
commit and re-runs `setup.sh` only when it changed (a `git fetch` otherwise).
So **a push to `main` reaches the next new session, and the pasted script
never needs editing.** Pin or roll back with the `CLOUD_SETUP_REF` variable:
new sessions use the new value (an already-open session keeps the old one).
Rolling back below the commit that added `session-start.sh` would stop the
self-update: pin a commit that contains it.

Limits: the setup script must finish in about 5 minutes, and a non-zero exit
fails the session. `bootstrap.sh` and `setup.sh` therefore treat every step as
non-fatal and always `exit 0`. Check the setup log for `⚠️` or `skipped` lines.

## Setting up an environment

On claude.ai/code, open the **environment menu in the session title bar →
Edit** (or create a new environment), then:

1. **Environment variables:** only what your tools need, e.g.
   `BRAID_SYNC_URL`, `BRAID_DOC_ID`, plus the `CLOUD_SETUP_*` variables of the
   [opt-in features](#opt-in-features) you want (e.g. `CLOUD_SETUP_R=release`).
   **No `GH_TOKEN`.** Anyone who uses the environment can read its variables.
   For HTTP API keys, prefer **API credentials** (Pro and Max plans): the proxy
   adds the key to requests and it never enters the container.
2. **Network access:** the default *Trusted* level covers GitHub and the
   package registries. With a custom allow-list, the opt-in features also
   need the hosts listed under *Network* in [Opt-in features](#opt-in-features).
3. **Setup script:** paste the full contents of [`bootstrap.sh`](bootstrap.sh)
   as is (`PIN="main"`), once. Don't edit it afterwards.

   **Trust model.** By default every new session follows `main`, as root,
   including the secret guard itself. That is fine while only the owner can
   push here (protect the GitHub account with 2FA). To freeze an environment
   on a reviewed commit instead, set the variable
   `CLOUD_SETUP_REF=<full 40-char SHA>` (short SHAs do not work). A
   `PIN="<SHA>"` already in a pasted script is honored too: the session hook
   follows what the bootstrap was asked for, and only `CLOUD_SETUP_REF`
   overrides it.

4. **Check it:** start a new session and ask Claude to run these as
   **separate commands** (the guard blocks a whole command if any part of it
   touches a secret):

   ```bash
   cloud-doctor              # hooks, installed commit, braid/gh versions, opt-in features, GH_TOKEN state, a real gh call, expected vars - no secrets printed
   echo "${BRAID_DOC_ID:-x}" # should be BLOCKED by secret-guard (proves PreToolUse works)
   printenv | wc -l          # should be BLOCKED too
   ```

   Don't judge GitHub access by `gh auth status`: behind the proxy it can
   report the token "invalid" while real calls work. `cloud-doctor` makes a
   real call (`gh api user`) instead.

## Day-to-day

| I want to... | Do |
|---|---|
| Update the setup | Merge to `main` (CI runs the tests). The next new session picks it up. Nothing to edit on claude.ai. |
| Freeze / roll back an environment | Set `CLOUD_SETUP_REF=<full SHA>` in its variables, start a new session. Unset it to follow `main` again. |
| Test a change first | Push a branch, set `CLOUD_SETUP_REF=<branch>` in a test environment, start a new session. |
| Add a tool | Add it to *Extra tools* in `setup.sh` (non-fatal, skip when already at the pinned version), record its version in the state file and check it in `session-start.sh` + `cloud-doctor.py`. Tools only one project needs belong in that project's own `SessionStart` hook instead. |
| Turn on a feature for one environment | Set its variable (see *Opt-in features* below) and start a new session. The session-start hook notices the change and installs it. |
| Change a feature's version | Change its variable (e.g. `CLOUD_SETUP_R=4.5.2`) and start a new session. Older versions stay on disk, so switching back is fast. |
| Add an opt-in feature | Add a `CLOUD_SETUP_<NAME>` block to the *Opt-in features* section of `setup.sh` (non-fatal, idempotent: resolve the wanted version first, skip when it is installed), record the variable in the state file, compare it in `features_ok` and show it in the status line (`session-start.sh`), report it in `cloud-doctor.py`, add a row to the table below and a CI job that installs it twice. |
| Add another environment | Repeat the setup steps. The pasted bootstrap is identical everywhere, only the variables differ. |
| Protect a new secret variable | Add its name to `SECRET_VARS` in `secret-guard.py`, and add a case to `test_secret_guard.py`. |

## Opt-in features

The pasted script is the same in every environment. An environment's
variables choose what else it gets:

| Variable | Values | Effect |
|---|---|---|
| `CLOUD_SETUP_QUARTO` | `release`, `prerelease`, or an exact version (`1.11.9`) | Installs Quarto from its GitHub release into `/opt/quarto/<version>`, linked as `~/.local/bin/quarto`. `release` and `prerelease` resolve the current version from quarto.org when setup runs. |
| `CLOUD_SETUP_R` | `release` or an exact version (`4.5.2`) | Installs [rig](https://github.com/r-lib/rig) (pinned in `setup.sh`, into `/usr/local`), then `rig add <version>`: Posit's R build for Ubuntu 24.04 in `/opt/R/<version>`, made the default and linked as `/usr/local/bin/R` and `Rscript`. rig also sets up the Posit Package Manager binary repository (fast `install.packages()`) and installs pak. `release` resolves the current version (`rig resolve`) when setup runs. Other rig specs (`4.5`, `oldrel`) work too, but are only checked for "some R is installed". |
| `CLOUD_SETUP_UV` | `latest` or an exact version (`0.13.7`) | Installs `uv` and `uvx` from their GitHub release into `~/.local/bin`, replacing the copy the image may ship (it can lag behind). `latest` resolves the newest stable tag when setup runs. Unset: the image's uv, if any, is left alone. |
| `CLOUD_SETUP_PYTHON` | one or more versions, space- or comma-separated (`3.12`, `3.12 3.14`, `3.12.13`) | Runs `uv python install <versions>`: uv-managed CPython in `~/.local/share/uv/python`, linked as `~/.local/bin/python3.X`. If no uv exists at all, installs the latest one first. |
| `CLOUD_SETUP_ATTRIBUTION` | `keep` | By default setup sets `"attribution": {"commit": "", "pr": ""}` in `~/.claude/settings.json`, so commits and PRs carry no Claude trailer or session link. `keep` leaves Claude Code's default attribution. |

Unset means not installed: no Quarto, no R, no extra Python. Unsetting a
variable later does not uninstall anything, it only stops the checks.

A healthy start shows what is installed in the session-start line, e.g.
`cloud-setup: up to date (rev 3a34e2e, braid 0.8.1, gh ok, quarto 1.12.0, R 4.6.2, uv 0.13.7, python 3.12 3.14)`.
`cloud-doctor` gives one line per requested feature.

**R notes.** Project packages don't belong here: keep them in the project
(renv or `DESCRIPTION`), installed from the Posit binaries in seconds. `R`
and `Rscript` come from `/usr/local/bin`; switching `CLOUD_SETUP_R` to an
installed version only changes rig's default.

**Python notes.** setup never runs `uv python install --default`, which
would put `python`/`python3` in `~/.local/bin`, ahead of the system
interpreter the hooks run with. So `python3` stays the image's, and the extra
versions are `python3.12`, `python3.14`, ... Projects choose one with
`.python-version` / `requires-python` or `uv run -p 3.12`. uv downloads a
missing version on demand anyway (a few seconds): `CLOUD_SETUP_PYTHON` only
puts it in the cached image ahead of time.

**Network.** Besides GitHub (release downloads, `git ls-remote`), the
features reach:

- Quarto `release`/`prerelease`: quarto.org.
- R: api.r-hub.io (rig resolving a version), cdn.posit.co (the R build),
  the Ubuntu apt mirrors (R's system dependencies), r-lib.github.io (pak),
  then packagemanager.posit.co and cloud.r-project.org for packages.
- uv and Python: GitHub releases only.

### When does a feature get installed?

Changing a variable does not rebuild the cached image, so the session-start
hook compares each variable with the value `setup.sh` last ran with and
re-runs it on a mismatch or a missing tool.

Until the cached image is rebuilt (setup script or network settings edited,
or after ~7 days), a feature added this way is installed again at the start
of each new session, since sessions start from the cached image. Measured in
a container: a few seconds for Quarto, uv or a Python version, about 30 s
for R (13 s for a second R version). The session-start hook allows `setup.sh`
4 minutes.

## What the secret guard covers

| Hook | Effect |
|---|---|
| `PreToolUse` | Denies env dumps (`env`, `printenv`, bare `export`, `set`, ...), xtrace, references to `$BRAID_DOC_ID`, `gh auth token` / `git-credential`, `git credential fill`, `braid secret`, `curl -v`, `/proc/*/environ`, and reads of `~/.git-credentials`, `~/.braid.toml` and `gh`'s `hosts.yml`. |
| `PostToolUse` | If the value of a variable in `SECRET_VARS` or a GitHub token pattern shows up in any tool output, replaces it (`updatedToolOutput`) with a redacted copy. |

**Limits:** it stops *accidental* leaks. An encoded secret (base64, split
across lines) is not recognized, and a deliberate read of the process
environment is not a threat it can stop. Keep secrets scoped and short-lived.

After editing `secret-guard.py`, run `python3 test_secret_guard.py`. CI runs
it too, along with `shellcheck`, a dry run of `setup.sh` and `session-start.sh`,
and one job per heavy opt-in feature (`opt-in-r` as root, `opt-in-uv`) that
installs it, then checks that a second run changes nothing.

## Keeping it public

Nothing here is secret, and it has to stay that way:

1. **Only variable *names* go in files, never values.** Secrets and private
   relay URLs go in the environment settings on claude.ai. Scripts read them
   from the environment, and the setup log only says whether each one is set.
2. **Don't reveal private things through the tool list.** Installing from a
   private repo, or listing project names, would publish them. Project-specific
   setup belongs in that project's own `SessionStart` hook.
3. **CI needs no secrets, so don't add any.** Keep GitHub's default behaviour
   that workflows on pull requests from forks run without your permissions.
4. **Only the owner can change this repo.** A push to `main` reaches every
   environment that follows `main` at its next new session. An environment
   with `CLOUD_SETUP_REF=<SHA>` only moves when you change that variable.
