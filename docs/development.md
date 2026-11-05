# Development

## Layout

| File | Role |
|---|---|
| `bootstrap.sh` | Pasted into the environment's Setup script. Options block, writes `~/.config/cloud-setup/defaults`, fetches this repo at `PIN`, runs `setup.sh`. Keep it small: changes reach an environment only when someone re-pastes it. |
| `setup.sh` | Installs tools and options, registers the hooks, writes the state file. Idempotent and fast when nothing changed: it may run at every new session. |
| `session-start.sh` | SessionStart hook: update, self-repair, report. |
| `secret-guard.py` | PreToolUse/PostToolUse hook. |
| `cloud-doctor.py` | Installed as `cloud-doctor`. Reports, never prints a secret. |
| `test_secret_guard.py` | Offline tests for the guard. |
| `docs/` | This documentation. |
| `CLAUDE.md`, `.claude/settings.json` | Rules for Claude sessions working on this repo: public repo, nothing personal, no attribution. |

## Rules for the scripts

- **Never fail**: every install ends with `|| echo "... skipped"`, and the
  scripts `exit 0`. A failing setup script blocks the session.
- **Don't read variables in the setup phase**: they are not set yet. Read
  options with `opt <NAME>` in `setup.sh`; check variables in
  `session-start.sh` or `cloud-doctor.py`.
- **Never print a secret**, not even in logs: print whether a variable is
  set, not its value.
- **Skip work already done** (installed at the wanted version), since
  `setup.sh` may re-run at every session.

## Tests and CI

`.github/workflows/test.yml` runs on every push and PR:

- `bash -n` and `shellcheck -S warning` on the shell scripts,
- `py_compile` and `test_secret_guard.py`,
- `setup.sh` in a scratch `HOME`, twice (hooks registered once),
- `session-start.sh` with braid on: healthy start, self-repair of a deleted
  tool, the `BRAID_SYNC_URL` warning,
- the options block with braid off: agent-browser installed from
  `defaults`, attribution kept, no braid and no braid warning, then
  agent-browser turned off by a variable,
- `opt-in-r` (as root, like the setup script), `opt-in-uv` and
  `opt-in-just`: install R, uv and two Python versions, just, then check
  that a second run changes nothing.

Locally:

```bash
python3 test_secret_guard.py
```

```bash
shellcheck -S warning *.sh
```

To try a branch in a real environment: push it, set
`CLOUD_SETUP_REF=<branch>` in a test environment, start a new session.

## Adding things

| To add | Do |
|---|---|
| A tool for every environment | *Extra tools* in `setup.sh` (non-fatal, skip when at the pinned version), record its version in the state file, check it in `session-start.sh` and `cloud-doctor.py`. A tool only one project needs belongs in that project's own `SessionStart` hook instead. |
| An opt-in feature | See [Adding an option](options.md#adding-an-option). |
| A secret variable to protect | Nothing to commit: list its name in the `CLOUD_SETUP_SECRET_VARS` option of your environment. Only a name that every user of a built-in tool needs (like braid's `BRAID_DOC_ID`) belongs in `SECRET_VARS` in `secret-guard.py`, with a test case. |

## Forking

1. Fork the repo.
2. In the `bootstrap.sh` you paste, set `REPO="https://github.com/<you>/<fork>"`.
   Otherwise your environments keep running the upstream repo's `main`, as
   root.
3. Your choices go in the options block and the environment settings, not
   in the code. If you need a new tool, add it as an option (see
   [Adding an option](options.md#adding-an-option)) so others can turn it off.

## Keeping it public

Nothing here is secret, and it has to stay that way:

1. **Only variable *names* go in files, never values.** Secrets and private
   relay URLs go in the environment settings on claude.ai. The options block
   holds feature choices, never secrets.
2. **Nothing personal, in files or in git history**: no names of private
   projects, talks, environments, machines or branches, not even as
   examples, and no session links. Commits carry no Claude attribution
   (`.claude/settings.json`); see `CLAUDE.md`. Personal choices are options.
3. **Don't reveal private things through the tool list.** Installing from a
   private repo, or listing project names, would publish them.
   Project-specific setup belongs in that project's own `SessionStart` hook.
4. **CI needs no secrets, so don't add any.** Keep GitHub's default that
   workflows on pull requests from forks run without your permissions.
5. **Only the owner can change this repo.** A push to `main` reaches every
   environment that follows `main` at its next new session.
