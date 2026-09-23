#!/usr/bin/env bash
# claude.ai/code cloud environment setup (run by bootstrap.sh from the
# environment's "Setup script"). Runs as root on Ubuntu 24.04, BEFORE Claude
# Code starts. The resulting filesystem is cached and reused by later sessions
# (rebuilt when the setup script or network settings change, or after ~7 days),
# so nothing session-specific or secret is written here.
#
# GitHub needs no token here: the platform's GitHub proxy authenticates `gh`
# and git for the repositories attached to the session. `gh` is installed only
# if the image doesn't already ship it.
#
# Every step is non-fatal: a failed install must never block a session.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
HOOKS_DIR="$HOME/.claude/hooks"
mkdir -p "$BIN_DIR" "$HOOKS_DIR"

step() { echo "==> $*"; }

# ============================================================================
# --- gh: only if missing (plain binary, no token, no wrapper)
# ============================================================================
install_gh() {
  # Latest stable tag via git: api.github.com is only reachable for repositories
  # attached to the session, github.com git reads of public repos always work.
  local ver w
  ver="$(git ls-remote --tags --refs https://github.com/cli/cli 'v*' \
         | sed 's#.*refs/tags/##' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
         | sort -V | tail -1)"
  ver="${ver#v}"
  [ -n "$ver" ] || { echo "could not determine latest gh version"; return 1; }
  w="$(mktemp -d)"
  curl -fsSL "https://github.com/cli/cli/releases/download/v${ver}/gh_${ver}_linux_amd64.tar.gz" -o "$w/gh.tgz" \
    && tar -xzf "$w/gh.tgz" -C "$w" \
    && install -m755 "$(find "$w" -type f -name gh -perm -u+x | head -1)" "$BIN_DIR/gh"
  local rc=$?
  rm -rf "$w"
  return $rc
}
step "gh"
if command -v gh >/dev/null && ! grep -q 'claude-cloud gh wrapper' "$(command -v gh)" 2>/dev/null; then
  echo "gh already installed: $(gh --version | head -1)"
else
  install_gh && echo "gh installed: $("$BIN_DIR/gh" --version | head -1)" \
    || echo "gh install skipped (non-fatal - check network access to github.com)"
fi

# ============================================================================
# --- Extra tools: add installs here (keep each one non-fatal with `|| echo`).
# ============================================================================
step "extra tools"
# e.g. uv tool install ruff || echo "ruff install skipped"

# ============================================================================
# --- Secret guard: keep secrets set on the environment (BRAID_DOC_ID, ...)
#   out of Claude's context.
#   PreToolUse:  deny commands that would dump secrets.
#   PostToolUse: redact secret values / GitHub token patterns from outputs.
# ============================================================================
step "secret-guard hooks"
install -m755 "$HERE/secret-guard.py" "$HOOKS_DIR/secret-guard.py"
install -m755 "$HERE/cloud-doctor.py" "$BIN_DIR/cloud-doctor"

# Register the hooks in user settings (merged, idempotent: every previous
# secret-guard entry - including the old SessionStart one - is replaced,
# anything else is kept).
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
for event in list(hooks):
    groups = [g for g in hooks[event]
              if not any("secret-guard.py" in h.get("command", "") for h in g.get("hooks", []))]
    if groups:
        hooks[event] = groups
    else:
        del hooks[event]
for event in ("PreToolUse", "PostToolUse"):
    hooks.setdefault(event, []).append({"matcher": "*", "hooks": [entry]})
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
PY
echo "secret-guard: hooks registered in ~/.claude/settings.json"

# --- Sanity warnings (non-fatal): catch a half-configured environment early.
for v in GH_TOKEN GITHUB_TOKEN; do
  case "${!v:-}" in
    ""|proxy-injected) ;;
    *) echo "⚠️  $v is set on the environment: it gives no extra GitHub access (the GitHub proxy decides) and anyone using the environment can read it - remove it" ;;
  esac
done
[ -n "${BRAID_SYNC_URL:-}" ] || echo "⚠️  BRAID_SYNC_URL unset - braid would use the PUBLIC relay wss://sync.automerge.org"
[ -n "${BRAID_DOC_ID:-}" ]   || echo "⚠️  BRAID_DOC_ID unset - no skein configured; create one with: braid init --sync-server \"\$BRAID_SYNC_URL\""
exit 0
