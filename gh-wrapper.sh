#!/usr/bin/env bash
# claude-cloud gh wrapper (installed by setup.sh as ~/.local/bin/gh).
# The GitHub token lives in a 600 file written by the secret-guard SessionStart
# hook, not in the Bash tool's environment; inject it only into `gh` itself.
self="$(readlink -f "$0")"
for c in "$HOME/.local/lib/gh/gh" /usr/local/bin/gh /usr/bin/gh; do
  # Skip ourselves (or another copy of this wrapper) to avoid an exec loop.
  [ -x "$c" ] && [ "$(readlink -f "$c")" != "$self" ] \
    && ! grep -q 'claude-cloud gh wrapper' "$c" 2>/dev/null && REAL="$c" && break
done
[ -n "${REAL:-}" ] || { echo "gh: real binary not found" >&2; exit 127; }
TOKEN_FILE="$HOME/.config/claude-secrets/gh_token"
[ -r "$TOKEN_FILE" ] && GH_TOKEN="$(cat "$TOKEN_FILE")" && export GH_TOKEN
exec "$REAL" "$@"
