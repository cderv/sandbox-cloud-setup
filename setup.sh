#!/usr/bin/env bash
# claude.ai/code cloud environment setup (run by bootstrap.sh from the
# environment's "Setup script"). Runs as root on Ubuntu 24.04, BEFORE Claude
# Code starts. The resulting filesystem is cached and reused by later sessions
# (rebuilt when the setup script or network settings change, or after ~7 days),
# so nothing session-specific - in particular no token - is written here: the
# secret-guard SessionStart hook handles that on every session.
#
# Every step is non-fatal: a failed install must never block a session.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
GH_LIB="$HOME/.local/lib/gh"
HOOKS_DIR="$HOME/.claude/hooks"
mkdir -p "$BIN_DIR" "$GH_LIB" "$HOOKS_DIR"

step() { echo "==> $*"; }

# ============================================================================
# --- gh: latest stable release, in $GH_LIB (the wrapper in $BIN_DIR calls it)
# ============================================================================
install_gh() {
  # Latest stable tag via git (no token, no api.github.com: some cloud
  # network policies block the API with 403 while github.com stays reachable).
  local ver w
  ver="$(git ls-remote --tags --refs https://github.com/cli/cli 'v*' \
         | sed 's#.*refs/tags/##' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
         | sort -V | tail -1)"
  ver="${ver#v}"
  [ -n "$ver" ] || { echo "could not determine latest gh version"; return 1; }
  w="$(mktemp -d)"
  curl -fsSL "https://github.com/cli/cli/releases/download/v${ver}/gh_${ver}_linux_amd64.tar.gz" -o "$w/gh.tgz" \
    && tar -xzf "$w/gh.tgz" -C "$w" \
    && install -m755 "$(find "$w" -type f -name gh -perm -u+x | head -1)" "$GH_LIB/gh"
  local rc=$?
  rm -rf "$w"
  return $rc
}
step "gh"
[ -x "$GH_LIB/gh" ] || install_gh || echo "gh install skipped (non-fatal - check network access to github.com)"
install -m755 "$HERE/gh-wrapper.sh" "$BIN_DIR/gh"

# ============================================================================
# --- Extra tools: add installs here (keep each one non-fatal with `|| echo`).
# ============================================================================
step "extra tools"
# e.g. uv tool install ruff || echo "ruff install skipped"

# ============================================================================
# --- Secrets hardening: keep GH_TOKEN / BRAID_DOC_ID out of Claude's context.
#   SessionStart: token -> 600 file, unset from every Bash tool command.
#   PreToolUse:   deny commands that would dump secrets.
#   PostToolUse:  redact secret values / GitHub token patterns from outputs.
# ============================================================================
step "secret-guard hooks"
install -m755 "$HERE/secret-guard.py" "$HOOKS_DIR/secret-guard.py"

# Register the hooks in user settings (merged, idempotent: previous
# secret-guard entries are replaced, anything else is kept).
python3 - "$HOME/.claude/settings.json" "$HOOKS_DIR/secret-guard.py" <<'PY'
import json, os, sys
path, hook = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        cfg = json.load(f)
except (OSError, ValueError):
    cfg = {}
hooks = cfg.setdefault("hooks", {})
entry = {"type": "command", "command": f"python3 {hook}"}
for event in ("SessionStart", "PreToolUse", "PostToolUse"):
    groups = [g for g in hooks.get(event, [])
              if not any("secret-guard.py" in h.get("command", "") for h in g.get("hooks", []))]
    groups.append({"matcher": "" if event == "SessionStart" else "*", "hooks": [entry]})
    hooks[event] = groups
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
PY
echo "secret-guard: hooks registered in ~/.claude/settings.json"

echo "gh: $("$BIN_DIR/gh" --version 2>/dev/null | head -1 || echo MISSING)"

# --- Sanity warnings (non-fatal): catch a half-configured environment early.
[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ] || echo "⚠️  GH_TOKEN unset - gh will be unauthenticated"
[ -n "${BRAID_SYNC_URL:-}" ] || echo "⚠️  BRAID_SYNC_URL unset - braid would use the PUBLIC relay wss://sync.automerge.org"
[ -n "${BRAID_DOC_ID:-}" ]   || echo "⚠️  BRAID_DOC_ID unset - no skein configured; create one with: braid init --sync-server \"\$BRAID_SYNC_URL\""
exit 0
