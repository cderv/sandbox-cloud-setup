#!/usr/bin/env bash
# Paste THIS into the claude.ai/code environment settings -> "Setup script".
# Fetches this (public) repo at PIN and runs setup.sh. No token needed.
# Never fails the session start: every problem is reported, then exit 0.
set -uo pipefail

# Paste once, never edit. Updates arrive by themselves: setup.sh installs a
# SessionStart hook that, on each new session, fetches this repo at
# CLOUD_SETUP_REF (default: main) and re-runs setup.sh when that commit changed.
# To pin or roll back, set CLOUD_SETUP_REF (branch, tag or full 40-char SHA)
# in the environment's variables: new sessions pick it up.
PIN="main"
REF="${CLOUD_SETUP_REF:-$PIN}"
REPO="${CLOUD_SETUP_REPO:-https://github.com/cderv/sandbox-cloud-setup}"
DEST=/opt/sandbox-cloud-setup

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
