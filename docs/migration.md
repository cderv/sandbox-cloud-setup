# Updating an existing environment

For environments set up with a `bootstrap.sh` that has no options block
(before the options block, braid opt-in and `REPO` in the block). Nothing
breaks if you do nothing, except:

- **braid is no longer installed by default.** An environment that uses it
  keeps the copy in its cached image, then loses it at the next image
  rebuild (about 7 days, or when the setup script or network settings
  change).
- Options set as variables (`CLOUD_SETUP_QUARTO`, ...) keep working, but are
  installed again at every new session.

These changes reach an environment when they are on the branch it follows
(`main` by default).

## Before you start

For each environment, note down from its dialog (environment selector →
settings icon → **Edit cloud environment**):

- [ ] its **Environment variables**: which `CLOUD_SETUP_*`, `BRAID_*`,
      `GH_TOKEN` it has,
- [ ] whether it **uses braid** (it has `BRAID_SYNC_URL` / `BRAID_DOC_ID`),
- [ ] whether its setup script or variables **pin a commit** (`PIN="<sha>"`
      or `CLOUD_SETUP_REF=<sha>`),
- [ ] its **Network access** level.

## Optional: try it on one environment first

1. Edit one environment. In its **Setup script**, paste the new
   [`bootstrap.sh`](../bootstrap.sh) with `PIN="<branch to test>"`.
2. Fill the options block (step 2 below), save, start a new session, check
   (step 5). Once the branch is merged, set `PIN="main"` again.

## For each environment

**1. Open the dialog.** Environment selector under the message box → hover
the environment → settings icon. (In a running session: the caret after the
session title → **Edit cloud environment**.)

**2. Setup script: replace it with the new [`bootstrap.sh`](../bootstrap.sh)**
(select all, paste, or **Choose file**), then fill its options block:

| If the environment... | Set in the block |
|---|---|
| uses braid | `CLOUD_SETUP_BRAID="0.8.1"` (the version your other peers use) |
| had the variable `CLOUD_SETUP_QUARTO=...` | `CLOUD_SETUP_QUARTO="..."` (same value) |
| had the variables `CLOUD_SETUP_R`, `CLOUD_SETUP_UV`, `CLOUD_SETUP_PYTHON` | the same values in the block (R also needs Custom network access) |
| had the variable `CLOUD_SETUP_ATTRIBUTION=keep` | `CLOUD_SETUP_ATTRIBUTION="keep"` |
| should have agent-browser | `CLOUD_SETUP_AGENT_BROWSER="latest"` |
| should have just | `CLOUD_SETUP_JUST="latest"` |
| has other secret variables than `BRAID_DOC_ID` | `CLOUD_SETUP_SECRET_VARS="NAME1,NAME2"` (names only) |
| was pinned with `PIN="<sha>"` | `PIN="<new full SHA>"` (see step 4) |
| uses a fork | `REPO="<your fork's URL>"` |

Leave the rest as is.

**3. Environment variables: remove what moved to the block.**

- Delete `CLOUD_SETUP_QUARTO`, `CLOUD_SETUP_R`, `CLOUD_SETUP_UV`,
  `CLOUD_SETUP_PYTHON`, `CLOUD_SETUP_ATTRIBUTION`, `CLOUD_SETUP_AGENT_BROWSER`,
  `CLOUD_SETUP_JUST` (now in the block). Keeping them is harmless
  (a variable wins over the block) but installs them at every session.
- Keep `BRAID_SYNC_URL` and `BRAID_DOC_ID` if the environment uses braid.
- Delete `GH_TOKEN` / `GITHUB_TOKEN` if present ([why](github.md)).

**4. Pinned commits.** If `CLOUD_SETUP_REF` or `PIN` holds a commit SHA,
check that the commit still exists in the repo (history rewrites change
SHAs). If not, set the new SHA, or remove the pin to follow `main`.

**5. Network access.** Trusted is enough, except for R (add its hosts
under **Custom**, see [R notes](options.md#r-notes)) and for the sites
agent-browser must open.

**6. Save** (**Save changes**). The next new session rebuilds the image,
so it takes a few minutes.

**7. Check.** Start a new session in the environment, then:

- Claude's context starts with `cloud-setup: up to date (rev ..., gh ok, ...)`,
  listing the tools you turned on (`braid 0.8.1`, `quarto ...`,
  `agent-browser ...`, `just ...`). A `cloud-setup WARNING` says what is wrong.
- Ask Claude to run `cloud-doctor`: every line `OK`, and each option shows
  `from bootstrap`.

## Quick fix without re-pasting

To only keep braid in an environment, add the **variable**
`CLOUD_SETUP_BRAID=0.8.1` and start a new session. It works with the old
`bootstrap.sh`; braid is already in the cached image, so nothing is
downloaded. Re-paste the new `bootstrap.sh` later, at your own pace.

## Environments that are not set up

An environment whose setup script is empty (like onboarding's **Default**)
has nothing to update. To use this setup there, follow the
[quick start](../README.md#quick-start); otherwise leave it as is.
