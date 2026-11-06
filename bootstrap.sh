#!/usr/bin/env bash
# Paste THIS into the claude.ai/code environment settings -> "Setup script".
# Fetches this (public) repo at PIN and runs setup.sh. No token needed.
# Never fails the session start: every problem is reported, then exit 0.
set -uo pipefail

# --- Options --------------------------------------------------------------
# The setup script runs BEFORE the environment's variables are set, so it
# cannot read them: options meant for the cached image go here. Editing this
# block rebuilds the cache, which is what you want (the feature is then
# installed once, not at every session). Empty = off. See docs/options.md.
#
# The same names set as environment VARIABLES also work and win over these,
# but are installed by the session-start hook at each new session (not cached).
CLOUD_SETUP_BRAID=""           # latest | exact version (0.8.1)
CLOUD_SETUP_QUARTO=""          # release | prerelease | exact version (1.11.9)
CLOUD_SETUP_R=""               # release | exact version (4.5.2); needs Custom network
CLOUD_SETUP_UV=""              # latest | exact version (0.13.7)
CLOUD_SETUP_PYTHON=""          # versions via uv, e.g. "3.12 3.14"
CLOUD_SETUP_AGENT_BROWSER=""   # latest | exact version (0.41.2)
CLOUD_SETUP_JUST=""            # latest | exact version (1.59.0)
CLOUD_SETUP_ATTRIBUTION=""     # keep = keep Claude's commit/PR attribution
CLOUD_SETUP_SECRET_VARS=""     # extra variable NAMES the secret guard protects,
                               # comma-separated (names only, never values)

# Which repo, and which version of it, to install. Updates arrive by
# themselves: a SessionStart hook fetches this ref at each new session and
# re-runs setup.sh when its commit changed. Pin with a tag or full 40-char
# SHA, or override per environment with the CLOUD_SETUP_REF variable (read by
# that hook). Using a fork? Put its URL in REPO.
REPO="https://github.com/cderv/sandbox-cloud-setup"
PIN="main"
# --------------------------------------------------------------------------

REF="${CLOUD_SETUP_REF:-$PIN}"
REPO="${CLOUD_SETUP_REPO:-$REPO}"
DEST=/opt/sandbox-cloud-setup

# Record the options: setup.sh, the hooks and cloud-doctor read them back as
# the defaults when the matching environment variable is unset.
mkdir -p "$HOME/.config/cloud-setup"
{
  echo "CLOUD_SETUP_BRAID=$CLOUD_SETUP_BRAID"
  echo "CLOUD_SETUP_QUARTO=$CLOUD_SETUP_QUARTO"
  echo "CLOUD_SETUP_R=$CLOUD_SETUP_R"
  echo "CLOUD_SETUP_UV=$CLOUD_SETUP_UV"
  echo "CLOUD_SETUP_PYTHON=$CLOUD_SETUP_PYTHON"
  echo "CLOUD_SETUP_AGENT_BROWSER=$CLOUD_SETUP_AGENT_BROWSER"
  echo "CLOUD_SETUP_JUST=$CLOUD_SETUP_JUST"
  echo "CLOUD_SETUP_ATTRIBUTION=$CLOUD_SETUP_ATTRIBUTION"
  echo "CLOUD_SETUP_SECRET_VARS=$CLOUD_SETUP_SECRET_VARS"
  echo "CLOUD_SETUP_REPO=$REPO"
} > "$HOME/.config/cloud-setup/defaults"

echo "bootstrap: installing $REPO @ $REF"
rm -rf "$DEST" && mkdir -p "$DEST"
# init + fetch <ref> works for a branch, a tag or a full commit SHA alike.
if git -C "$DEST" init -q \
   && git -C "$DEST" fetch -q --depth 1 "$REPO" "$REF" \
   && git -C "$DEST" -c advice.detachedHead=false checkout -q FETCH_HEAD; then
  echo "bootstrap: at commit $(git -C "$DEST" rev-parse HEAD)"
  bash "$DEST/setup.sh" || echo "bootstrap: setup.sh failed (non-fatal)"
else
  echo "bootstrap: could not fetch $REPO @ $REF (network? typo in PIN?) - skipping"
fi
exit 0
