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
# Besides gh and braid, it installs the opt-in features that the environment's
# CLOUD_SETUP_* variables ask for (Quarto, R via rig, uv, uv-managed Python):
# see the "Opt-in features" section below and the README.
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
BRAID_VER="0.8.1"
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
# --- Opt-in features: each environment turns them on with a variable, the
#     pasted script never changes. Unset = not installed. session-start.sh
#     re-runs this file when a requested feature is missing or its variable
#     changed (a variable change alone does not rebuild the cached image).
#
#   CLOUD_SETUP_QUARTO      = release | prerelease | <exact version, e.g. 1.11.9>
#   CLOUD_SETUP_R           = release | <exact version, e.g. 4.5.2> (via rig)
#   CLOUD_SETUP_UV          = latest | <exact version, e.g. 0.13.7>
#   CLOUD_SETUP_PYTHON      = <versions, e.g. "3.12 3.14"> (uv-managed)
#   CLOUD_SETUP_ATTRIBUTION = keep  (default: no Claude attribution in commits
#                                    and PRs; applied with the hooks below)
# ============================================================================
QUARTO_WANT="${CLOUD_SETUP_QUARTO:-}"
R_WANT="${CLOUD_SETUP_R:-}"
UV_WANT="${CLOUD_SETUP_UV:-}"
PYTHON_WANT="${CLOUD_SETUP_PYTHON:-}"

# quarto_resolve <spec>: release/prerelease -> current version from quarto.org.
quarto_resolve() {
  local url
  case "$1" in
    release)    url="https://quarto.org/docs/download/_download.json" ;;
    prerelease) url="https://quarto.org/docs/download/_prerelease.json" ;;
    *)          echo "$1"; return 0 ;;
  esac
  curl -fsSL "$url" | python3 -c 'import sys, json; print(json.load(sys.stdin)["version"])'
}

# install_quarto <version>: GitHub release tarball into /opt/quarto/<version>,
# linked as $BIN_DIR/quarto. Older versions stay on disk (switching back is free).
install_quarto() {
  local ver="$1" dest="/opt/quarto/$1" w rc
  w="$(mktemp -d)"
  curl -fsSL "https://github.com/quarto-dev/quarto-cli/releases/download/v${ver}/quarto-${ver}-linux-amd64.tar.gz" -o "$w/quarto.tgz" \
    && rm -rf "$dest" && mkdir -p "$dest" \
    && tar -xzf "$w/quarto.tgz" -C "$dest" --strip-components=1 \
    && ln -sf "$dest/bin/quarto" "$BIN_DIR/quarto"
  rc=$?
  rm -rf "$w"
  return $rc
}

if [ -n "$QUARTO_WANT" ]; then
  step "quarto ($QUARTO_WANT)"
  quarto_ver="$(quarto_resolve "$QUARTO_WANT" 2>/dev/null)"
  quarto_got="$("$BIN_DIR/quarto" --version 2>/dev/null)"
  if [ -z "$quarto_ver" ]; then
    echo "quarto: could not resolve '$QUARTO_WANT' from quarto.org (kept: ${quarto_got:-none})"
  elif [ "$quarto_got" = "$quarto_ver" ]; then
    echo "quarto already installed: $quarto_got"
  elif install_quarto "$quarto_ver"; then
    echo "quarto installed: $("$BIN_DIR/quarto" --version 2>/dev/null || echo '?')"
  else
    echo "quarto install skipped (non-fatal - check network access to github.com)"
  fi
fi

# --- R via rig (https://github.com/r-lib/rig). rig is pinned like braid: bump
#     deliberately. It installs into /usr/local (bin/rig), and `rig add` (admin
#     mode, as root) installs Posit's R build for Ubuntu 24.04 into
#     /opt/R/<version>, links R/Rscript in /usr/local/bin and sets up the
#     Posit Package Manager binary repo (fast install.packages()) and pak.
#     Project packages do NOT belong here: they go in the project (renv or
#     DESCRIPTION).
RIG_VER="0.11.1"
RIG="/usr/local/bin/rig"

# install_rig: GitHub release tarball (bin/, share/) unpacked into /usr/local.
install_rig() {
  local w rc
  w="$(mktemp -d)"
  curl -fsSL "https://github.com/r-lib/rig/releases/download/v${RIG_VER}/rig-linux-$(uname -m)-${RIG_VER}.tar.gz" -o "$w/rig.tgz" \
    && tar -xzf "$w/rig.tgz" -C /usr/local
  rc=$?
  rm -rf "$w"
  return $rc
}

# r_installed: version of the default R (rig's quick link), empty if none.
r_installed() {
  /usr/local/bin/Rscript -e 'cat(format(getRversion()))' 2>/dev/null
}

if [ -n "$R_WANT" ]; then
  step "R ($R_WANT, rig v$RIG_VER)"
  if "$RIG" --version 2>/dev/null | grep -q " $RIG_VER\$"; then
    echo "rig already installed: $("$RIG" --version 2>/dev/null | head -1)"
  elif install_rig; then
    echo "rig installed: $("$RIG" --version 2>/dev/null | head -1)"
  else
    echo "rig install skipped (non-fatal - check network access to github.com)"
  fi
  # release -> current version (rig asks api.r-hub.io), x.y.z -> itself.
  r_ver="$("$RIG" resolve "$R_WANT" 2>/dev/null | awk 'NR==1 {print $1}')"
  r_got="$(r_installed)"
  if [ -z "$r_ver" ]; then
    echo "R: could not resolve '$R_WANT' with rig (kept: ${r_got:-none})"
  elif [ "$r_got" = "$r_ver" ]; then
    echo "R already installed: $r_got"
  elif "$RIG" add "$r_ver" && "$RIG" default "$r_ver"; then
    echo "R installed: $(r_installed || echo '?')"
  else
    echo "R install skipped (non-fatal - check network access to cdn.posit.co)"
  fi
fi

# --- uv (https://github.com/astral-sh/uv): the image may already ship one in
#     ~/.local/bin; CLOUD_SETUP_UV pins or upgrades it from the GitHub release
#     (same place, so it replaces the image's copy).
# uv_version <uv>: "0.13.7", empty if missing.
uv_version() { "$1" --version 2>/dev/null | awk '{print $2}'; }

# uv_resolve <spec>: latest -> newest stable tag (git, like gh above).
uv_resolve() {
  case "$1" in
    latest) git ls-remote --tags --refs https://github.com/astral-sh/uv \
              | sed 's#.*refs/tags/##' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
              | sort -V | tail -1 ;;
    *) echo "$1" ;;
  esac
}

# install_uv <version>: release tarball, uv + uvx into $BIN_DIR.
install_uv() {
  local ver="$1" t w rc
  t="uv-$(uname -m)-unknown-linux-gnu"
  w="$(mktemp -d)"
  curl -fsSL "https://github.com/astral-sh/uv/releases/download/${ver}/${t}.tar.gz" -o "$w/uv.tgz" \
    && tar -xzf "$w/uv.tgz" -C "$w" \
    && install -m755 "$w/$t/uv" "$w/$t/uvx" "$BIN_DIR/"
  rc=$?
  rm -rf "$w"
  return $rc
}

# Python versions need a uv: install the latest one if there is none at all.
[ -n "$PYTHON_WANT" ] && [ -z "$UV_WANT" ] && ! command -v uv >/dev/null 2>&1 \
  && [ ! -x "$BIN_DIR/uv" ] && UV_WANT=latest
if [ -n "$UV_WANT" ]; then
  step "uv ($UV_WANT)"
  uv_ver="$(uv_resolve "$UV_WANT" 2>/dev/null)"
  uv_got="$(uv_version "$BIN_DIR/uv")"
  if [ -z "$uv_ver" ]; then
    echo "uv: could not resolve '$UV_WANT' (kept: ${uv_got:-none})"
  elif [ "$uv_got" = "$uv_ver" ]; then
    echo "uv already installed: $uv_got"
  elif install_uv "$uv_ver"; then
    echo "uv installed: $(uv_version "$BIN_DIR/uv" || echo '?')"
  else
    echo "uv install skipped (non-fatal - check network access to github.com)"
  fi
fi

# --- Python versions managed by uv (~/.local/share/uv/python, linked as
#     ~/.local/bin/python3.X). Never --default: that would put python/python3
#     in ~/.local/bin, ahead of the system python3 the hooks run with. Projects
#     pick a version with .python-version / requires-python, or uv run -p 3.X.
if [ -n "$PYTHON_WANT" ]; then
  step "python ($PYTHON_WANT, via uv)"
  uv_bin="$BIN_DIR/uv"; [ -x "$uv_bin" ] || uv_bin="$(command -v uv)"
  # shellcheck disable=SC2086 # word splitting is the point: one arg per version
  if [ -z "$uv_bin" ]; then
    echo "python skipped: no uv (set CLOUD_SETUP_UV)"
  elif UV_NO_PROGRESS=1 "$uv_bin" python install ${PYTHON_WANT//,/ }; then
    echo "python installed: $("$uv_bin" python list --only-installed --managed-python 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
  else
    echo "python install skipped (non-fatal - check network access to github.com)"
  fi
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
# No Co-Authored-By trailer or session link in commits and PRs, unless the
# environment sets CLOUD_SETUP_ATTRIBUTION=keep.
if os.environ.get("CLOUD_SETUP_ATTRIBUTION") == "keep":
    cfg.pop("attribution", None)
else:
    cfg["attribution"] = {"commit": "", "pr": ""}
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
  echo "quarto=$QUARTO_WANT"
  echo "r=$R_WANT"
  echo "uv=${CLOUD_SETUP_UV:-}"
  echo "python=$PYTHON_WANT"
  echo "attribution=${CLOUD_SETUP_ATTRIBUTION:-}"
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
