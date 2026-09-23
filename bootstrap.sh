#!/usr/bin/env bash
# Paste THIS into the claude.ai/code environment settings -> "Setup script".
# Fetches this (public) repo at PIN and runs setup.sh. No token needed.
# Never fails the session start: every problem is reported, then exit 0.
set -uo pipefail

# Which version to install. Edit THIS line to update or pin: editing the setup
# script is what makes claude.ai/code rebuild its cached environment (changing
# an environment variable alone does not). Prefer a commit SHA you reviewed;
# use the full 40-char SHA. A branch or tag also works. CLOUD_SETUP_REF, if set, overrides it.
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
