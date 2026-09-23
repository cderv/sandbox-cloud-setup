# sandbox-cloud-setup

A reproducible, hardened setup for Claude Code on the web (claude.ai/code)
environments. It installs the tools, and it keeps `GH_TOKEN` and similar
secrets out of Claude's context.

This repo is **public on purpose**: it holds no secrets, so the setup script
can fetch it without a token. Secret *values* live only in the environment
settings on claude.ai (see [Keeping it public](#keeping-it-public)).

| File | Role |
|---|---|
| `bootstrap.sh` | The only thing pasted into claude.ai. Fetches this repo at `PIN` and runs `setup.sh`. |
| `setup.sh` | Installs `gh` (behind a wrapper) and any extra tools, then registers the secret-guard hooks. |
| `secret-guard.py` | A Claude Code hook: moves the token out of Claude's environment, blocks commands that would print secrets, and redacts secrets from tool output. |
| `gh-wrapper.sh` | Installed as `~/.local/bin/gh`. Gives the token to `gh` only. |
| `cloud-doctor.py` | Installed as `~/.local/bin/cloud-doctor`. Checks the setup and prints no secrets. |
| `test_secret_guard.py` | Offline tests for the guard, also run in CI. |

## How claude.ai/code runs it

A claude.ai/code **environment** is a reusable config: environment variables,
network access, and a **setup script**. Each session in that environment gets
a fresh Ubuntu 24.04 container, set up like this:

```
1. SETUP SCRIPT (root, before Claude Code starts, result CACHED)
   bootstrap.sh
     ├─ reads PIN / CLOUD_SETUP_REF  → which commit/tag/branch of this repo
     ├─ fetches that version into /opt/sandbox-cloud-setup (public, no token)
     └─ runs setup.sh
          ├─ gh release        → ~/.local/lib/gh/gh
          ├─ gh-wrapper.sh     → ~/.local/bin/gh   (first on PATH)
          ├─ extra tools
          └─ secret-guard.py   → ~/.claude/hooks/, registered in ~/.claude/settings.json

2. CLAUDE CODE STARTS (every session, including resumed ones)
   SessionStart hook (secret-guard.py)
     ├─ writes GH_TOKEN to ~/.config/claude-secrets/gh_token (mode 600)
     └─ writes `unset GH_TOKEN GITHUB_TOKEN` to $CLAUDE_ENV_FILE

3. EVERY TOOL CALL
   PreToolUse  → deny commands that would print a secret (env dump, set -x,
                 echo $GH_TOKEN, gh auth token, ...)
   Bash        → runs without GH_TOKEN; `gh` still works, because its wrapper
                 reads the 600 file
   PostToolUse → if a secret or GitHub token appears in the output, Claude gets
                 a redacted copy instead
```

### The cache: when does setup.sh actually run?

claude.ai/code **saves the container state produced by the setup script and
reuses it** for later sessions. The setup script re-runs, and the cache is
rebuilt, only when:

- the **setup script text is edited**,
- the environment's **network settings change**, or
- the cache is about **7 days** old.

Changing an environment **variable** is not listed as a trigger, and neither
is a **push to this repo**. A resumed session never re-runs setup. Two
consequences:

1. **To roll out a new version, edit the `PIN="..."` line in the
   pasted setup script.** That edit is what forces the rebuild. Setting the
   `CLOUD_SETUP_REF` variable still overrides `PIN`, but may not rebuild on its
   own.
2. **No secret is written at setup time**, because it would be frozen into the
   cache. The token file is written by the `SessionStart` hook in every
   session, so a rotated `GH_TOKEN` is picked up at the next session.

Limits: the setup script must finish in about 5 minutes, and a non-zero exit
fails the session. `bootstrap.sh` and `setup.sh` therefore treat every step as
non-fatal and always `exit 0`. Check the setup log for `⚠️` or `skipped` lines.

## Setting up an environment (step by step)

On claude.ai/code, open the **environment menu in the session title bar →
Edit** (or create a new environment), then:

### 1. Create the token

On GitHub, create a **fine-grained personal access token**:

- Repository access: only the repos your sessions should use with `gh`, with
  only the permissions they need. The bootstrap does **not** need it, because
  this repo is public.
- Do **not** grant *Gists* or write access to this repo. A cloud session must
  never be able to change its own setup.
- A short expiry. The guard stops *accidental* leaks. It is not a sandbox.

### 2. Environment variables

```
GH_TOKEN=<the token>
# optional:
BRAID_SYNC_URL=...
BRAID_DOC_ID=...
CLOUD_SETUP_REF=<sha|tag|branch>   # temporary override of PIN, e.g. to test a branch
```

### 3. Network access

`github.com` must be reachable. It is used for the fetch and the `gh` release
download. The default trusted-hosts policy covers it.

### 4. Setup script

Paste the full contents of [`bootstrap.sh`](bootstrap.sh), then set the pin:

```bash
PIN="<full 40-char commit SHA>"   # recommended: a commit on main you reviewed (short SHAs do not work)
# or
PIN="main"         # follow main (updates only when the cache rebuilds)
```

**Pin to a SHA.** The setup script runs as root before Claude starts. With
`PIN="main"`, anything pushed to `main` (including a push by a Claude session
with write access) is installed the next time the cache rebuilds, and that
includes the secret guard itself.

### 5. Check it

Start a new session in the environment and ask Claude to run each of these
**as separate commands**. The guard blocks a whole command if any part of it
touches a secret.

```bash
cloud-doctor              # hooks, token file, token format, a real gh call - never prints the token
echo "${GH_TOKEN:-unset}" # should be BLOCKED by secret-guard (proves PreToolUse works)
printenv | wc -l          # should be BLOCKED too
```

> **Don't use `gh auth status` to check the token here.** Inside the
> claude.ai/code container it reports "The token in GH_TOKEN is invalid" even
> when the token is valid and every real call (`gh api user`, `gh pr list`, ...)
> works. Outgoing traffic goes through the environment's egress proxy, which
> handles authentication to `api.github.com`, and that confuses gh's own check.
> Test with a real call instead: `gh api user --jq .login`.

If `cloud-doctor` reports a problem:

- **Token file missing:** `GH_TOKEN` isn't set on the environment.
- **Format problem** (quotes, whitespace, `GH_TOKEN=` inside the value): fix
  the variable's value in the environment settings.
- **`gh api user` fails:** check the network policy, and whether the token has
  expired.

The setup log starts with `bootstrap: at commit <sha>`, so you can confirm
which version ran. If nothing is blocked, check the setup log for the
`secret-guard: hooks registered` line.

## Day-to-day

| I want to... | Do |
|---|---|
| Update the setup | Merge to `main` (CI runs the tests), then change `PIN` to the new SHA in each environment's setup script. |
| Test a change first | Push a branch, then in a test environment set `PIN="<branch>"` (or `CLOUD_SETUP_REF`) and start a new session. |
| Add a tool | Add a line to *Extra tools* in `setup.sh`, ending in `\|\| echo "... skipped"` so a failure never blocks a session. Tools only one project needs belong in that project's own `SessionStart` hook instead. |
| Add another environment | Repeat steps 1–4. The pasted bootstrap is identical everywhere, only `PIN` and the variables differ. |
| Rotate the token | Update `GH_TOKEN` on the environment. The next session picks it up, with no rebuild needed. |

## What the secret guard covers

| Hook | Effect |
|---|---|
| `SessionStart` | Copies the token to `~/.config/claude-secrets/gh_token` (600) and unsets `GH_TOKEN`/`GITHUB_TOKEN` for every Bash command, through `$CLAUDE_ENV_FILE`. |
| `PreToolUse` | Denies env dumps (`env`, `printenv`, bare `export`, `set`, ...), xtrace, `$GH_TOKEN`/`$BRAID_DOC_ID` references, `gh auth token` / `git-credential`, `git credential fill`, `braid secret`, `curl -v`, `/proc/*/environ`, and any access to the secret paths. |
| `PostToolUse` | If a secret value or a GitHub token pattern shows up in any tool output, replaces it (`updatedToolOutput`) with a redacted copy. |

**Limits:** a same-user process can still read the token file on purpose, and
an encoded token (base64, split across lines) is not recognized. MCP tools
such as the GitHub connector use their own auth and are unaffected.

After editing `secret-guard.py`, run `python3 test_secret_guard.py`. CI runs
it too, along with `shellcheck` and a dry run of `setup.sh`.

## Keeping it public

Nothing here is secret, and it has to stay that way:

1. **Only variable *names* go in files, never values.** Tokens, the braid doc
   id and private relay URLs (`BRAID_SYNC_URL`) go in the environment settings
   on claude.ai. Scripts read them from the environment, and the setup log only
   says whether each one is set.
2. **Don't reveal private things through the tool list.** Installing from a
   private repo, or listing project names, would publish them. Project-specific
   setup belongs in that project's own `SessionStart` hook.
3. **CI needs no secrets, so don't add any.** Keep GitHub's default behaviour
   that workflows on pull requests from forks run without your permissions.
4. **Only the owner can change this repo.** Pinning `PIN` to a SHA means even
   a change to `main` reaches an environment only when you move the pin.
