# Cloud environments

A **cloud environment** is the saved configuration a cloud session runs in:
network access level, environment variables, network secrets and setup
script. The same environments apply to claude.ai/code, the Desktop and mobile
apps, `claude --cloud`, cloud scheduled tasks and Claude Tag.
([docs](https://code.claude.com/docs/en/cloud-environments))

## Configured by hand, in the UI

There is **no public API or CLI to create or edit an environment** (checked
2026-11-04):

- **claude.ai/code or the Desktop app**: on the new-session screen, the
  environment selector is the first control under the message box.
  - **New environment**, at the bottom of its menu, creates one.
  - To edit one, hover it under **Cloud** (or **More**) and select its
    settings icon.
  - In a running session: the caret after the session title, then
    **Edit cloud environment**.
- **Team/Enterprise Owners**: [admin settings → Cloud environments](https://claude.ai/admin-settings)
  to create, edit and archive *shared* environments. A personal environment
  can also be shared from its **Who can use it** row.
- **CLI**: `/remote-env` only picks which existing environment
  `claude --cloud` uses (saved as `remote.defaultEnvironmentId`). It cannot
  add or edit one.
- **From a session**: Claude can *list* your environments (name, id, kind)
  and start a session in a given one, but not change their settings.

Environments cannot be deleted, only **archived** (from the same dialog).
Running sessions keep working; new sessions cannot pick it any more.

What this repo automates is everything *after* the one paste of
[`bootstrap.sh`](../bootstrap.sh).

## The Default environment

Onboarding creates **Default**: Trusted network access, **no variables, no
setup script**. Sessions in it start with only the image's pre-installed
tools, and none of this setup. To use this setup, either paste
`bootstrap.sh` into Default, or create a dedicated environment and pick it in
the selector.

With several environments, a new session uses the one shown in the selector
(the last one you picked). Threads in a project use the project's setting.

## The four settings

| Setting | What to put there | Notes |
|---|---|---|
| **Setup script** | The full [`bootstrap.sh`](../bootstrap.sh), with your [options](options.md) set in its block. **Choose file** loads it from disk (up to 64 KB). | Runs as root before Claude Code starts, **without the environment variables**, and its result is cached. See [How it works](how-it-works.md). |
| **Network access** | **Trusted** (default) for the setup itself. **Custom** to add domains, **Full** for everything, **None** for offline. | Under Trusted, only package registries, GitHub and an allowlist are reachable (e.g. `example.com` is refused). Changing it rebuilds the cache. |
| **Environment variables** | `.env` format, one `KEY=value` per line: what your tools need (e.g. `BRAID_SYNC_URL`, `BRAID_DOC_ID` for braid), optionally `CLOUD_SETUP_*` overrides. | Anyone who uses the environment can read them. Quote a value that contains `#`. A running session picks up a change only when its VM restarts; start a new session to be sure. Never `GH_TOKEN` ([why](github.md)). |
| **Network secrets** | API keys for HTTP APIs: name, allowed hosts, header. | The agent proxy adds the key to matching requests, so it **never enters the VM**. Prefer this over a variable for any API key. Not applied to GitHub, the Anthropic API, package registries, or requests from the setup script. |

## Checking an environment

Start a new session in it and look for the `cloud-setup:` line in Claude's
context, or ask Claude to run `cloud-doctor`. Then ask Claude to run these as
**separate commands** (the guard blocks a whole command if any part of it
touches a secret):

```bash
cloud-doctor              # hooks, installed commit, tools, options and where each comes from, GH_TOKEN, a real gh call
echo "${BRAID_DOC_ID:-x}" # should be BLOCKED by secret-guard (works even if unset)
printenv | wc -l          # should be BLOCKED too
```

## Several environments

The pasted `bootstrap.sh` is the same everywhere. What differs between
environments is its options block (what gets installed), the variables, and
the network level. Example:

| Environment | Options block | Network |
|---|---|---|
| Docs work | `CLOUD_SETUP_QUARTO="release"` | Trusted |
| Synced notes | `CLOUD_SETUP_BRAID="0.8.1"` | Trusted, plus the relay's host under Custom if it is not allowlisted |
| Web testing | `CLOUD_SETUP_AGENT_BROWSER="latest"` | Custom: the sites under test |
| Plain | (nothing) | Trusted |
