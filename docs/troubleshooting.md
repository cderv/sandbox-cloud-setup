# Troubleshooting

Start with `cloud-doctor` (safe: prints no secret). The session-start log is
`~/.cache/cloud-setup-session.log`. The setup script's own output is not
kept in the VM; look for `skipped` lines where your client shows the setup
step (e.g. the checklist `claude --cloud` prints).

| Symptom | Cause / fix |
|---|---|
| `cloud-doctor: command not found`, no `cloud-setup:` line at session start | The environment's setup script is not `bootstrap.sh` (e.g. the **Default** environment). Paste it ([environments](environments.md)) and start a **new** session: existing sessions are not upgraded. |
| An option is installed again at every session | It is set as an environment variable, which the setup script cannot see. Move it to the [options block](options.md). |
| An option in the block is not installed | Check that the edited script was saved (**Save changes**), then start a new session: editing the script rebuilds the image. `cloud-doctor` shows where each option value comes from. |
| `cloud-setup WARNING: could not fetch ...` | Typo in `CLOUD_SETUP_REF`/`PIN`, a short SHA, or GitHub unreachable. The session keeps the installed commit. |
| `cloud-setup WARNING: ... update to <sha> failed` / `repair run failed` | `setup.sh` failed during the session. See the session-start log. |
| `cloud-setup WARNING: opt-in feature not installed as requested` | The install was skipped (network?). The log says which step; `cloud-doctor` shows wanted vs installed. |
| `quarto: could not resolve 'release'` | Neither raw.githubusercontent.com nor quarto.org answered. Use an exact version (`CLOUD_SETUP_QUARTO="1.11.9"`): it downloads straight from GitHub releases. Environments set up before this fix asked quarto.org only, which Trusted refuses. |
| `R: could not resolve 'release' with rig` / `R install skipped` | R's hosts are not on the Trusted list. Use **Custom** network access with the hosts in [R notes](options.md#r-notes). |
| `BRAID_SYNC_URL unset` warning | braid is on (`CLOUD_SETUP_BRAID`) but its relay is not set: set `BRAID_SYNC_URL` in the environment's variables, or turn braid off. |
| `cloud-setup WARNING: no repository recorded` | The installed state does not say which repo it came from. Set `REPO` in the pasted script (or the `CLOUD_SETUP_REPO` variable) and start a new session. |
| braid is gone after an update | braid is now opt-in: add `CLOUD_SETUP_BRAID="0.8.1"` to the options block ([Updating an environment](migration.md)). |
| `GH_TOKEN is set on the environment` warning | Remove it: the GitHub proxy authenticates `gh`, and the token is readable by anyone using the environment ([GitHub](github.md)). |
| `gh pr view` / `gh issue list` fail with 403 | GraphQL is refused by the GitHub proxy. Use `gh api repos/OWNER/REPO/...`. |
| `GitHub access to ... is not enabled for this session` | The repository is not attached to the session. Attach it (ask Claude) or start the session with it. |
| No `justfile:` line in Claude's context at session start | The line needs `just` on the machine (`CLOUD_SETUP_JUST`) and a `justfile`, `Justfile` or `.justfile` at the project root. It is left out when `just --summary` fails or takes more than 5 s, or the justfile has no public recipe; above 20 recipes it gives only their count. Run `just --summary` in the project to see why ([justfile notes](options.md#justfile-notes)). |
| agent-browser: `net::ERR_TUNNEL_CONNECTION_FAILED` | The site is not allowed by the network level. Add it under **Custom** network access ([agent-browser](agent-browser.md#browser-and-network)). |
| agent-browser: `ERR_CERT_AUTHORITY_INVALID` | Run with the normal `HOME` (`/root`): the proxy CA is in `/root/.pki/nssdb`. |
| A command is blocked by secret-guard | It would print a secret, or part of it matched. Split the command; never print the secret itself ([secret guard](secret-guard.md)). |
| A new session takes minutes to start | The setup script is running (first session after an edit, a network change, or the 7-day expiry). Later sessions start from the cache. |
