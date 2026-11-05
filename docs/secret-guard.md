# Secret guard

`secret-guard.py` is one Claude Code hook, registered for two events in
`~/.claude/settings.json`. Its purpose: keep secrets set on the environment
out of Claude's context, and so out of the transcript: `BRAID_DOC_ID`, plus
the names you list in the `CLOUD_SETUP_SECRET_VARS` option.

| Hook | Effect |
|---|---|
| `PreToolUse` | Denies env dumps (`env`, `printenv`, bare `export`, `set`, ...), xtrace (`bash -x`, `set -x`), references to `$BRAID_DOC_ID` and the `CLOUD_SETUP_SECRET_VARS` names, `gh auth token` / `git-credential`, `git credential fill`, `braid secret`, `curl -v`/`--trace`, `/proc/*/environ`, and reads of `~/.git-credentials`, `~/.braid.toml` and `gh`'s `hosts.yml`. |
| `PostToolUse` | If the value of one of those variables, or a GitHub token pattern, shows up in any tool output, Claude gets a redacted copy (`updatedToolOutput`) instead. |

It blocks a **whole command** when any part of it matches, so run checks as
separate commands.

## Limits

- It stops **accidental** leaks. An encoded secret (base64, split across
  lines) is not recognized, and a deliberate read of the process environment
  is not a threat it can stop. It is not a sandbox.
- It fails open on its own errors: a bug in the guard never breaks a tool
  call.
- Environment variables are readable by anyone who uses the environment. For
  an HTTP API key, a **network secret** is better: the key never enters the
  VM ([environments](environments.md#the-four-settings)).

## Protecting your own secrets

List the variable **names** in the `CLOUD_SETUP_SECRET_VARS` option,
comma-separated, in the bootstrap's options block or as an environment
variable: `CLOUD_SETUP_SECRET_VARS="MY_API_KEY,OTHER_TOKEN"`. The guard reads
it at every tool call, so a change applies to new sessions without a
rebuild. Nothing to commit here: your names stay in your environment.
`cloud-doctor` lists the protected names.

Better still, store an HTTP API key as a **network secret**: it then never
enters the VM at all.
