#!/usr/bin/env bash
# SessionStart hook (installed by setup.sh): keeps the environment current
# WITHOUT editing the pasted setup script, then checks the expected tools.
#
# The cached environment is only rebuilt when the pasted setup script or the
# network settings change, or after ~7 days. So on each new or resumed
# session this hook fetches this repo at the ref the pasted bootstrap asked
# for (its PIN, recorded by setup.sh; main by default), or CLOUD_SETUP_REF if
# set, and only when that commit differs from the installed one, re-runs
# setup.sh (idempotent). Pin or roll back by setting CLOUD_SETUP_REF on the
# environment: new sessions pick it up.
#
# Then it checks braid / gh against what setup.sh recorded. A problem is
# reported to the user (systemMessage) and to Claude (additionalContext);
# a healthy start adds one short line to Claude's context. Never fails the
# session: always exit 0. Prints no secret (variable names only).
set -uo pipefail

# tools_ok <state-file>: braid at the recorded version, gh present, and the
# opt-in features match the environment's variables.
tools_ok() {
  local want
  want="$(sed -n 's/^braid=//p' "$1" 2>/dev/null)"
  [ -n "$want" ] \
    && [[ "$("$HOME/.local/bin/braid" --version 2>/dev/null)" == *"$want"* ]] \
    && command -v gh >/dev/null 2>&1 \
    && features_ok "$1"
}

# features_ok <state-file>: each CLOUD_SETUP_<FEATURE> variable is the one
# setup.sh last ran with, and what it asks for is installed. A variable added
# or changed on the environment fails this, so the repair step installs it.
features_ok() {
  local q="${CLOUD_SETUP_QUARTO:-}"
  [ "${CLOUD_SETUP_ATTRIBUTION:-}" = "$(sed -n 's/^attribution=//p' "$1" 2>/dev/null)" ] || return 1
  [ "$q" = "$(sed -n 's/^quarto=//p' "$1" 2>/dev/null)" ] || return 1
  [ -z "$q" ] && return 0
  case "$q" in
    release|prerelease) "$HOME/.local/bin/quarto" --version >/dev/null 2>&1 ;;
    *) [ "$("$HOME/.local/bin/quarto" --version 2>/dev/null)" = "$q" ] ;;
  esac
}

main() {
  local ref repo base_ref base_repo dir state log have_rev new_rev braid_want braid_got msg ran=""
  local -a problems=()
  dir="$HOME/.cache/sandbox-cloud-setup"
  state="$HOME/.config/cloud-setup/state"
  log="$HOME/.cache/cloud-setup-session.log"
  mkdir -p "$HOME/.cache"
  : > "$log"

  # What to follow: CLOUD_SETUP_REF / CLOUD_SETUP_REPO if set, otherwise what
  # the pasted bootstrap asked for (ref= / repo= recorded by setup.sh: a
  # pinned PIN stays pinned). No record -> stay on the installed commit.
  have_rev="$(sed -n 's/^rev=//p' "$state" 2>/dev/null)"
  base_ref="$(sed -n 's/^ref=//p' "$state" 2>/dev/null)"
  base_ref="${base_ref:-$have_rev}"
  base_repo="$(sed -n 's/^repo=//p' "$state" 2>/dev/null)"
  base_repo="${base_repo:-https://github.com/cderv/sandbox-cloud-setup}"
  ref="${CLOUD_SETUP_REF:-$base_ref}"
  repo="${CLOUD_SETUP_REPO:-$base_repo}"
  # setup.sh re-run from here must keep recording the bootstrap's choice.
  export CLOUD_SETUP_BASE_REF="$base_ref" CLOUD_SETUP_BASE_REPO="$base_repo"

  # --- 1. refresh: re-run setup.sh only when the wanted commit changed
  if [ -z "$ref" ]; then
    problems+=("no setup state and no CLOUD_SETUP_REF - nothing to follow")
  elif { [ -d "$dir/.git" ] || git init -q "$dir"; } \
     && timeout 20 git -C "$dir" fetch -q --depth 1 "$repo" "$ref" >>"$log" 2>&1; then
    new_rev="$(git -C "$dir" rev-parse FETCH_HEAD)"
    # Always check out (cheap): the repair step below needs the files too.
    if ! git -C "$dir" -c advice.detachedHead=false checkout -q -f FETCH_HEAD >>"$log" 2>&1; then
      problems+=("checkout of ${new_rev:0:7} failed (log: $log)")
    elif [ "$new_rev" != "$have_rev" ]; then
      ran=1
      timeout 240 bash "$dir/setup.sh" >>"$log" 2>&1 \
        || problems+=("update to ${new_rev:0:7} failed (log: $log)")
    fi
  else
    problems+=("could not fetch $ref from $repo (network? typo in CLOUD_SETUP_REF?) - kept ${have_rev:0:7}")
  fi

  # --- 1b. self-repair: a tool is missing or at the wrong version -> re-run
  #         setup.sh once from the current checkout (e.g. a failed install).
  if [ -z "$ran" ] && [ -f "$dir/setup.sh" ] && ! tools_ok "$state"; then
    timeout 240 bash "$dir/setup.sh" >>"$log" 2>&1 || problems+=("repair run failed (log: $log)")
  fi

  # --- 2. check the expected tools (versions recorded by setup.sh)
  have_rev="$(sed -n 's/^rev=//p' "$state" 2>/dev/null)"
  braid_want="$(sed -n 's/^braid=//p' "$state" 2>/dev/null)"
  braid_got="$("$HOME/.local/bin/braid" --version 2>/dev/null)"
  if [ -z "$braid_want" ]; then
    problems+=("no setup state in $state - setup.sh never completed")
  elif [[ "$braid_got" != *"$braid_want"* ]]; then
    problems+=("braid ${braid_got:-missing}, expected $braid_want")
  fi
  command -v gh >/dev/null 2>&1 || problems+=("gh missing")
  features_ok "$state" || problems+=("opt-in feature not installed as requested (CLOUD_SETUP_QUARTO=${CLOUD_SETUP_QUARTO:-unset})")
  [ -n "${BRAID_SYNC_URL:-}" ] || problems+=("BRAID_SYNC_URL unset - braid would use the PUBLIC relay")

  # --- 3. report
  if [ "${#problems[@]}" -eq 0 ]; then
    local extra=""
    [ -n "${CLOUD_SETUP_QUARTO:-}" ] && extra=", quarto $("$HOME/.local/bin/quarto" --version 2>/dev/null)"
    echo "cloud-setup: up to date (rev ${have_rev:0:7}, ${braid_got:-braid ?}, gh ok${extra})"
  else
    msg="cloud-setup WARNING: $(IFS=';'; echo "${problems[*]}"). Tell the user; run cloud-doctor for details."
    python3 -c 'import json,sys; m=sys.argv[1]; print(json.dumps({"systemMessage": m, "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": m}}))' "$msg"
  fi
}

# Wrapped in main + exit: setup.sh may reinstall this very file while it runs.
main "$@"
exit 0
