# How it works

## Three phases

```
1. SETUP SCRIPT (root, before Claude Code starts, NO environment variables, result CACHED)
   bootstrap.sh
     ├─ options block → ~/.config/cloud-setup/defaults
     ├─ fetches REPO at PIN into /opt/sandbox-cloud-setup (public, no token)
     └─ runs setup.sh
          ├─ gh (only if missing) → ~/.local/bin/gh
          ├─ options              → braid, quarto, R (rig), uv, python, just, agent-browser (+ skill), attribution
          ├─ secret-guard.py + session-start.sh → ~/.claude/hooks/, registered in ~/.claude/settings.json
          └─ ~/.config/cloud-setup/state  (rev=, ref=, repo=, braid=, and each option's value)

2. EVERY NEW OR RESUMED SESSION (SessionStart hook, variables visible, NOT cached)
   session-start.sh
     ├─ fetches CLOUD_SETUP_REPO/REF, else the bootstrap's REPO/PIN (unknown repo → no update)
     ├─ that commit != rev= ?  → re-runs its setup.sh (idempotent)
     ├─ a tool missing, or an option's wanted value != the state ? → re-runs setup.sh once
     └─ reports: one line to Claude when healthy, a warning to you otherwise

3. EVERY TOOL CALL
   PreToolUse  → deny commands that would print a secret
   PostToolUse → redact secret values and GitHub tokens from the output
```

Every step is non-fatal: a non-zero exit of the setup script would fail the
session, so `bootstrap.sh` and `setup.sh` always `exit 0` and report problems
as `skipped` lines in the setup log. The session-start hook always exits 0
too, and reports problems as a warning.

## The cache

claude.ai/code **snapshots the filesystem the setup script produced and
starts every later session from that snapshot**. The setup script runs
again, and the snapshot is rebuilt, only when:

- the **setup script text is edited** (e.g. its options block),
- the environment's **network settings change**, or
- the snapshot is about **7 days** old.

Consequences:

- **A variable change or a push to this repo does not rebuild it.** That is
  why updates go through the session-start hook.
- **What a session changes is not saved back.** Every new session starts from
  the snapshot again. So when the hook updates to a newer commit, or
  installs an option set as a variable, every new session repeats it until
  the next rebuild. That is quick when nothing new must be downloaded, and
  is why heavy options belong in the options block.
- **The setup script must finish in about 5 minutes**, or the environment is
  not cached at all.
- A resumed session whose VM was only paused keeps its files and does not
  re-run the setup script.

## Self-update

`session-start.sh` runs at every new or resumed session. It fetches this repo
at the wanted ref (`git fetch --depth 1`, 20 s timeout) and re-runs that
commit's `setup.sh` only when the commit differs from `rev=` in the state
file. So **a push to `main` reaches the next new session, and the pasted
script never needs editing for updates.**

## Pinning and the trust model

By default every new session follows `main`, as root, including the secret
guard itself. That is fine while only the owner can push here (protect the
GitHub account with 2FA). To freeze an environment on a reviewed commit:

- `PIN="<full 40-char SHA>"` in the pasted script (rebuilds the cache), or
- the variable `CLOUD_SETUP_REF=<full SHA>` (read by the session-start hook;
  short SHAs do not work). It wins over `PIN`. Unset it to follow `PIN`
  again.

The hook follows what the pasted bootstrap asked for (`ref=`/`repo=` in the
state file, read back from git's `FETCH_HEAD`). If the ref is unknown, it
stays on the installed commit; if the repo is unknown, it does not update at
all, rather than silently following some default repository's `main`.

Rolling back below the commit that added `session-start.sh` would stop the
self-update: pin a commit that contains it.

## Files it writes

| Path | Written by | Content |
|---|---|---|
| `/opt/sandbox-cloud-setup/` | `bootstrap.sh` | Checkout used by the setup script. |
| `~/.cache/sandbox-cloud-setup/` | `session-start.sh` | Checkout used by the session hook. |
| `~/.cache/cloud-setup-session.log` | `session-start.sh` | Log of the last session-start run (fetch, setup.sh output). |
| `~/.config/cloud-setup/defaults` | `bootstrap.sh` | The options block, one `CLOUD_SETUP_*=value` per line, plus `CLOUD_SETUP_REPO`. |
| `~/.config/cloud-setup/state` | `setup.sh` | `rev=`, `ref=`, `repo=`, `braid=`, and each option's value it ran with. |
| `~/.claude/hooks/secret-guard.py`, `~/.claude/hooks/cloud-setup-session-start.sh` | `setup.sh` | The hooks. |
| `~/.claude/settings.json` | `setup.sh` | Hook registration (merged, idempotent) and `attribution`. Other keys are kept. |
| `~/.local/bin/{gh,braid,quarto,just,agent-browser,cloud-doctor}` | `setup.sh` | Tools (`gh` only if the image lacks it). |
| `/opt/quarto/<version>/`, `/opt/agent-browser/<version>/`, `/opt/R/<version>/` (+ `/usr/local/bin/{rig,R,Rscript}`), `~/.local/share/uv/python/` | `setup.sh` | Opt-in installs. |
| `~/.agent-browser/config.json`, `~/.claude/skills/agent-browser/` | `setup.sh` | agent-browser browser path and skill. |

`HOME` is `/root` in the cloud VM.
