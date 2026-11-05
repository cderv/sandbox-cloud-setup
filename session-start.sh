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
# Then it checks gh and the opt-in features against what setup.sh recorded. A problem is
# reported to the user (systemMessage) and to Claude (additionalContext);
# a healthy start adds one short line to Claude's context. Never fails the
# session: always exit 0. Prints no secret (variable names only).
set -uo pipefail

# tools_ok <state-file>: setup.sh completed, gh present, and the opt-in
# features match their wanted values.
tools_ok() {
  grep -q '^rev=.' "$1" 2>/dev/null \
    && command -v gh >/dev/null 2>&1 \
    && features_ok "$1"
}

# opt <NAME>: wanted value of option CLOUD_SETUP_<NAME>, same rule as setup.sh:
# the environment variable when set, otherwise the pasted bootstrap's options
# block (~/.config/cloud-setup/defaults). "off" = disabled.
opt() {
  local name="CLOUD_SETUP_$1" v
  v="${!name:-}"
  [ -n "$v" ] || v="$(sed -n "s/^$name=//p" "$HOME/.config/cloud-setup/defaults" 2>/dev/null | tail -1)"
  [ "$v" = "off" ] && v=""
  printf '%s' "$v"
}

# version_ok <spec> <command>: the tool runs, and is at <spec> unless <spec>
# is a moving name (release, prerelease, latest), which setup.sh resolved.
version_ok() {
  local got
  got="$("$2" --version 2>/dev/null)" || return 1
  case "$1" in
    release|prerelease|latest) [ -n "$got" ] ;;
    *) [ "${got##* }" = "$1" ] ;;
  esac
}

# features_ok <state-file>: each option's wanted value is the one setup.sh
# last ran with, and what it asks for is installed. An option added or
# changed on the environment fails this, so the repair step installs it.
features_ok() {
  local b q ab j r r_got
  b="$(opt BRAID)"; b="${b#v}"; q="$(opt QUARTO)"; ab="$(opt AGENT_BROWSER)"; r="$(opt R)"
  j="$(opt JUST)"
  [ "$(opt ATTRIBUTION)" = "$(sed -n 's/^attribution=//p' "$1" 2>/dev/null)" ] || return 1
  [ "$b" = "$(sed -n 's/^braid=//p' "$1" 2>/dev/null)" ] || return 1
  [ "$q" = "$(sed -n 's/^quarto=//p' "$1" 2>/dev/null)" ] || return 1
  [ "$ab" = "$(sed -n 's/^agent_browser=//p' "$1" 2>/dev/null)" ] || return 1
  [ "$j" = "$(sed -n 's/^just=//p' "$1" 2>/dev/null)" ] || return 1
  [ "$r" = "$(sed -n 's/^r=//p' "$1" 2>/dev/null)" ] || return 1
  uv_ok "$1" && python_ok "$1" || return 1
  { [ -z "$b" ] || version_ok "$b" "$HOME/.local/bin/braid"; } \
    && { [ -z "$q" ] || version_ok "$q" "$HOME/.local/bin/quarto"; } \
    && { [ -z "$ab" ] || version_ok "$ab" "$HOME/.local/bin/agent-browser"; } \
    && { [ -z "$j" ] || version_ok "$j" "$HOME/.local/bin/just"; } \
    || return 1
  # R: an exact x.y.z must match; release (or any rig alias) only needs an R.
  [ -z "$r" ] && return 0
  r_got="$(r_version)"
  [ -n "$r_got" ] || return 1
  [[ "$r" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 0
  [ "$r_got" = "$r" ]
}

# uv_bin: the uv setup.sh manages (~/.local/bin), else whatever is on PATH.
uv_bin() {
  if [ -x "$HOME/.local/bin/uv" ]; then echo "$HOME/.local/bin/uv"; else command -v uv; fi
}

# uv_ok <state-file>: the UV option as recorded; an exact version must match.
uv_ok() {
  local u got
  u="$(opt UV)"
  [ "$u" = "$(sed -n 's/^uv=//p' "$1" 2>/dev/null)" ] || return 1
  [ -z "$u" ] && return 0
  got="$("$(uv_bin)" --version 2>/dev/null | awk '{print $2}')"
  [ -n "$got" ] && { [ "$u" = latest ] || [ "$got" = "$u" ]; }
}

# python_ok <state-file>: the PYTHON option as recorded, and uv finds a
# uv-managed interpreter for each requested version.
python_ok() {
  local p v uv
  p="$(opt PYTHON)"
  [ "$p" = "$(sed -n 's/^python=//p' "$1" 2>/dev/null)" ] || return 1
  [ -z "$p" ] && return 0
  uv="$(uv_bin)"; [ -n "$uv" ] || return 1
  for v in ${p//,/ }; do
    "$uv" python find --managed-python "$v" >/dev/null 2>&1 || return 1
  done
}

# just_hint: one line for Claude's context when the session's project has a
# justfile and just is installed: its public recipes, or only their count
# when there are many. Empty otherwise, and on any error (never fails).
# `just --summary` parses the justfile without running anything.
just_hint() {
  local dir="${CLAUDE_PROJECT_DIR:-$PWD}" jb f s n
  jb="$HOME/.local/bin/just"; [ -x "$jb" ] || jb="$(command -v just 2>/dev/null)" || return 0
  for f in justfile Justfile .justfile; do
    [ -f "$dir/$f" ] && break
    f=""
  done
  [ -n "$f" ] || return 0
  s="$(timeout 5 "$jb" --justfile "$dir/$f" --working-directory "$dir" --summary 2>/dev/null)" || return 0
  n="$(wc -w <<<"$s")"
  [ "$n" -gt 0 ] || return 0
  if [ "$n" -le 20 ]; then
    echo "justfile: recipes ${s//$'\n'/ } - prefer \`just <recipe>\` for these tasks."
  else
    echo "justfile: $n recipes (run \`just --list\`) - prefer \`just <recipe>\` for these tasks."
  fi
}

# r_version: version of the default R that rig linked in /usr/local/bin.
r_version() {
  /usr/local/bin/Rscript -e 'cat(format(getRversion()))' 2>/dev/null
}

main() {
  local ref repo base_ref base_repo dir state log have_rev new_rev msg ran=""
  local -a problems=()
  dir="$HOME/.cache/sandbox-cloud-setup"
  state="$HOME/.config/cloud-setup/state"
  log="$HOME/.cache/cloud-setup-session.log"
  mkdir -p "$HOME/.cache"
  : > "$log"

  # What to follow: CLOUD_SETUP_REF / CLOUD_SETUP_REPO if set, otherwise what
  # the pasted bootstrap asked for (ref= / repo= recorded by setup.sh: a
  # pinned PIN stays pinned). No record -> stay on the installed commit, and
  # never fall back to some default repository.
  have_rev="$(sed -n 's/^rev=//p' "$state" 2>/dev/null)"
  base_ref="$(sed -n 's/^ref=//p' "$state" 2>/dev/null)"
  base_ref="${base_ref:-$have_rev}"
  base_repo="$(sed -n 's/^repo=//p' "$state" 2>/dev/null)"
  ref="${CLOUD_SETUP_REF:-$base_ref}"
  repo="${CLOUD_SETUP_REPO:-$base_repo}"
  # setup.sh re-run from here must keep recording the bootstrap's choice.
  export CLOUD_SETUP_BASE_REF="$base_ref" CLOUD_SETUP_BASE_REPO="$base_repo"

  # --- 1. refresh: re-run setup.sh only when the wanted commit changed
  if [ -z "$ref" ]; then
    problems+=("no setup state and no CLOUD_SETUP_REF - nothing to follow")
  elif [ -z "$repo" ]; then
    problems+=("no repository recorded and no CLOUD_SETUP_REPO - not updating, kept ${have_rev:0:7}")
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
  [ -n "$have_rev" ] || problems+=("no setup state in $state - setup.sh never completed")
  command -v gh >/dev/null 2>&1 || problems+=("gh missing")
  features_ok "$state" || problems+=("opt-in feature not installed as requested (braid=$(opt BRAID), quarto=$(opt QUARTO), R=$(opt R), uv=$(opt UV), python=$(opt PYTHON), agent-browser=$(opt AGENT_BROWSER), just=$(opt JUST))")
  if [ -n "$(opt BRAID)" ] && [ -z "${BRAID_SYNC_URL:-}" ]; then
    problems+=("BRAID_SYNC_URL unset - braid would use the PUBLIC relay")
  fi
  local v
  for v in GH_TOKEN GITHUB_TOKEN; do
    case "${!v:-}" in
      ""|proxy-injected) ;;
      *) problems+=("$v is set on the environment: it gives no extra GitHub access and anyone using the environment can read it - remove it") ;;
    esac
  done

  # --- 3. report (plus the project's justfile recipes, for Claude only)
  local hint
  hint="$(just_hint)"
  if [ "${#problems[@]}" -eq 0 ]; then
    local extra=""
    [ -n "$(opt BRAID)" ] && extra+=", $("$HOME/.local/bin/braid" --version 2>/dev/null)"
    [ -n "$(opt QUARTO)" ] && extra+=", quarto $("$HOME/.local/bin/quarto" --version 2>/dev/null)"
    [ -n "$(opt R)" ] && extra+=", R $(r_version)"
    [ -n "$(opt UV)" ] && extra+=", uv $("$(uv_bin)" --version 2>/dev/null | awk '{print $2}')"
    [ -n "$(opt PYTHON)" ] && extra+=", python $(p="$(opt PYTHON)"; echo "${p//,/ }")"
    [ -n "$(opt AGENT_BROWSER)" ] && extra+=", $("$HOME/.local/bin/agent-browser" --version 2>/dev/null)"
    [ -n "$(opt JUST)" ] && extra+=", $("$HOME/.local/bin/just" --version 2>/dev/null)"
    echo "cloud-setup: up to date (rev ${have_rev:0:7}, gh ok${extra})"
    [ -z "$hint" ] || echo "$hint"
  else
    msg="cloud-setup WARNING: $(IFS=';'; echo "${problems[*]}"). Tell the user; run cloud-doctor for details."
    python3 -c 'import json,sys; m, h = sys.argv[1], sys.argv[2]; print(json.dumps({"systemMessage": m, "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": m + ("\n" + h if h else "")}}))' "$msg" "$hint"
  fi
}

# Wrapped in main + exit: setup.sh may reinstall this very file while it runs.
main "$@"
exit 0
