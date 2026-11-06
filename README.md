# sandbox-cloud-setup

A reproducible setup for Claude Code **cloud environments** (claude.ai/code,
the Desktop and mobile apps, `claude --cloud`). You paste one script into an
environment's **Setup script**, once. Every session in that environment then
gets:

- **`gh`**, if the image lacks it,
- **opt-in features** chosen per environment: [braid](https://github.com/cscheid/braid),
  Quarto, R (via rig), uv and Python, [just](https://github.com/casey/just),
  [agent-browser](docs/agent-browser.md),
  commit/PR attribution on or off,
  extra secret variable names to protect,
- **a secret guard** hook that keeps environment secrets out of Claude's context,
- **self-updates**: a push to `main` reaches the next new session, with nothing to edit on claude.ai,
- **`cloud-doctor`**, a command that checks all of the above without printing secrets.

The repo is **public on purpose**: it holds no secrets, so the setup script
fetches it without a token. See [Keeping it public](docs/development.md#keeping-it-public).

## Quick start

Environments can only be configured in the UI: there is no API or CLI for
that ([details](docs/environments.md)).

1. At [claude.ai/code](https://claude.ai/code), open the **environment
   selector** under the message box: **New environment**, or the settings
   icon on an existing one.
2. **Setup script**: paste [`bootstrap.sh`](bootstrap.sh) and turn on what you
   want in its options block:

   ```bash
   CLOUD_SETUP_BRAID=""                # latest | 0.8.1
   CLOUD_SETUP_QUARTO="release"        # release | prerelease | 1.11.9
   CLOUD_SETUP_R=""                    # release | 4.5.2 (needs Custom network)
   CLOUD_SETUP_UV=""                   # latest | 0.13.7
   CLOUD_SETUP_PYTHON=""               # "3.12 3.14" (via uv)
   CLOUD_SETUP_AGENT_BROWSER="latest"  # latest | 0.41.2
   CLOUD_SETUP_JUST=""                 # latest | 1.59.0
   CLOUD_SETUP_ATTRIBUTION=""          # keep = keep Claude's commit/PR trailers
   CLOUD_SETUP_SECRET_VARS=""          # MY_API_KEY,OTHER_TOKEN (names only)
   REPO="https://github.com/cderv/sandbox-cloud-setup"   # your fork's URL, if any
   PIN="main"
   ```

   Nothing personal goes in this repo: your choices live in this block and
   in the environment's settings.

3. **Network access**: **Trusted** is enough for the setup. Pick **Custom**
   to let Claude (or the browser) reach other sites.
4. **Environment variables**: only what your tools need (e.g.
   `BRAID_SYNC_URL` and `BRAID_DOC_ID` for braid). Never `GH_TOKEN`.
5. Save, start a **new session**, and ask Claude to run `cloud-doctor`.

A healthy session starts with a line like
`cloud-setup: up to date (rev 2fa7bfa, gh ok, agent-browser 0.41.2)`
in Claude's context. If `cloud-doctor` is not found, the environment is not
set up. That is the case of the **Default** environment onboarding creates.

## Documentation

| Page | What's in it |
|---|---|
| [Environments](docs/environments.md) | Creating and editing environments in the UI, Default and shared environments, variables vs network secrets, network levels, which environment a session uses. |
| [Options](docs/options.md) | Every opt-in feature, the two places to set one (options block or variable) and why, adding a new one. |
| [agent-browser](docs/agent-browser.md) | What it is, what setup does, the browser and the network. |
| [How it works](docs/how-it-works.md) | The three phases (setup script, session start, tool calls), the cache, self-update, pinning and the trust model, the files it writes. |
| [GitHub in the sandbox](docs/github.md) | The GitHub proxy, why there is no token, GraphQL, branch names, forks. |
| [Secret guard](docs/secret-guard.md) | What it blocks and redacts, and its limits. |
| [Sandbox facts](docs/sandbox-facts.md) | Checked facts about the cloud VM (paths, proxy, allowlist, cache), with dates and sources. |
| [Updating an environment](docs/migration.md) | Step by step, for environments set up with an older `bootstrap.sh`. |
| [Troubleshooting](docs/troubleshooting.md) | Symptoms and fixes. |
| [Development](docs/development.md) | Repo layout, tests and CI, adding a tool, forking, keeping the repo public. |
