#!/usr/bin/env bash
# claude.ai/code cloud environment setup (run by bootstrap.sh from the
# environment's "Setup script"). Runs as root on Ubuntu 24.04, BEFORE Claude
# Code starts. The resulting filesystem is cached and reused by later sessions
# (rebuilt when the setup script or network settings change, or after ~7 days),
# so nothing session-specific or secret is written here.
#
# The pasted setup script never needs editing: session-start.sh (installed
# below as a SessionStart hook) re-runs this file at session start whenever
# CLOUD_SETUP_REF (default: main) points to another commit. So this file must
# stay idempotent and fast when nothing changed.
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

# --- braid (automerge sync client): the official signed + sha256-verified
#     installer, fetched at the pinned tag. Bump deliberately and keep every
#     peer (laptop, cloud) on the same version. minisign (optional) lets the
#     installer check the Ed25519 release signature; without it, checksum only.
BRAID_VER="0.7.0"
step "braid v$BRAID_VER"
if "$BIN_DIR/braid" --version 2>/dev/null | grep -q "$BRAID_VER"; then
  echo "braid already installed: $("$BIN_DIR/braid" --version)"
else
  command -v minisign >/dev/null 2>&1 \
    || { apt-get update -qq && apt-get install -y -qq minisign; } >/dev/null 2>&1 || true
  skip=""; command -v minisign >/dev/null 2>&1 || skip="--insecure-skip-signature"
  w="$(mktemp -d)"
  if curl -fsSL "https://raw.githubusercontent.com/cscheid/braid/v${BRAID_VER}/install.sh" -o "$w/install.sh" \
     && bash "$w/install.sh" --version "v${BRAID_VER}" --dest "$BIN_DIR" $skip; then
    echo "braid installed: $("$BIN_DIR/braid" --version 2>/dev/null || echo '?')"
  else
    echo "braid install skipped (non-fatal - check network access to github.com)"
  fi
  rm -rf "$w"
fi

# ============================================================================
# --- Secret guard: keep secrets set on the environment (BRAID_DOC_ID, ...)
#   out of Claude's context.
#   PreToolUse:  deny commands that would dump secrets.
#   PostToolUse: redact secret values / GitHub token patterns from outputs.
# ============================================================================
step "secret-guard + session-start hooks"
install -m755 "$HERE/secret-guard.py" "$HOOKS_DIR/secret-guard.py"
install -m755 "$HERE/session-start.sh" "$HOOKS_DIR/cloud-setup-session-start.sh"
install -m755 "$HERE/cloud-doctor.py" "$BIN_DIR/cloud-doctor"

# Register the hooks in user settings (merged, idempotent: every previous
# secret-guard / session-start entry - including the old secret-guard
# SessionStart one - is replaced, anything else is kept).
python3 - "$HOME/.claude/settings.json" "$HOOKS_DIR/secret-guard.py" "$HOOKS_DIR/cloud-setup-session-start.sh" <<'PY'
import json, os, sys
path, hook, start = sys.argv[1], sys.argv[2], sys.argv[3]
ours = ("secret-guard.py", "cloud-setup-session-start.sh")
try:
    with open(path) as f:
        cfg = json.load(f)
except (OSError, ValueError):
    cfg = {}
hooks = cfg.setdefault("hooks", {})
entry = {"type": "command", "command": f"python3 {hook}"}
for event in list(hooks):
    groups = [g for g in hooks[event]
              if not any(o in h.get("command", "") for o in ours for h in g.get("hooks", []))]
    if groups:
        hooks[event] = groups
    else:
        del hooks[event]
for event in ("PreToolUse", "PostToolUse"):
    hooks.setdefault(event, []).append({"matcher": "*", "hooks": [entry]})
hooks.setdefault("SessionStart", []).append(
    {"matcher": "startup|resume",
     "hooks": [{"type": "command", "command": f"bash {start}", "timeout": 300}]})
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
PY
echo "secret-guard + session-start: hooks registered in ~/.claude/settings.json"

# --- Record what was installed: session-start.sh compares the wanted commit
#     with rev=, follows ref=/repo= unless CLOUD_SETUP_REF overrides, and
#     checks the tools against these versions.
#     ref=/repo= = what the pasted bootstrap asked for (its PIN, read back from
#     git's FETCH_HEAD: "branch 'main' of URL", "'<sha>' of URL", ...), so a
#     pinned bootstrap stays pinned. When session-start re-runs this file it
#     passes the original choice in CLOUD_SETUP_BASE_REF/_REPO. Unknown ->
#     pin to the installed commit (fail-safe: never silently follow main).
rev="$(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo unknown)"
fetched="$(cut -f3 "$HERE/.git/FETCH_HEAD" 2>/dev/null | head -1)"
base_ref="${CLOUD_SETUP_BASE_REF:-$(printf '%s' "$fetched" | sed -n "s/^[a-z]* *'\(.*\)' of .*/\1/p")}"
base_repo="${CLOUD_SETUP_BASE_REPO:-$(printf '%s' "$fetched" | sed -n 's/.* of //p')}"
mkdir -p "$HOME/.config/cloud-setup"
{
  echo "rev=$rev"
  echo "ref=${base_ref:-$rev}"
  echo "repo=${base_repo:-https://github.com/cderv/sandbox-cloud-setup}"
  echo "braid=$BRAID_VER"
} > "$HOME/.config/cloud-setup/state"

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
