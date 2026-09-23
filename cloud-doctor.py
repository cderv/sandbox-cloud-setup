#!/usr/bin/env python3
"""cloud-doctor: check this environment's setup WITHOUT printing any secret.

Installed as ~/.local/bin/cloud-doctor by setup.sh. Safe to run from a Claude
session: it reports only metadata (format, length, whitespace/quotes) and the
result of a real `gh api user` call, never the token itself.
"""
import json
import os
import re
import stat
import subprocess

HOME = os.path.expanduser("~")
TOKEN_FILE = os.path.join(HOME, ".config/claude-secrets/gh_token")
SETTINGS = os.path.join(HOME, ".claude/settings.json")


def line(ok, label, detail=""):
    print(f"{'OK ' if ok else '!! '} {label}{': ' + detail if detail else ''}")


def token_shape(t):
    if t.startswith("github_pat_"):
        kind = "fine-grained PAT (github_pat_)"
    elif re.match(r"gh[pousr]_", t):
        kind = f"GitHub token ({t[:4]})"
    else:
        kind = "UNRECOGNIZED format (not ghp_/github_pat_ - pasted the wrong thing?)"
    problems = []
    if re.search(r"\s", t):
        problems.append("contains whitespace")
    if t[:1] in "\"'" or t[-1:] in "\"'":
        problems.append("wrapped in quotes")
    if t.upper().startswith("GH_TOKEN="):
        problems.append("value starts with 'GH_TOKEN=' (put only the token in the value)")
    return kind, problems


def gh_works():
    """A real API call through the gh wrapper. Not `gh auth status`: inside the
    claude.ai/code container that check reports the token invalid even when
    every real call succeeds (the egress proxy handles api.github.com auth)."""
    p = subprocess.run(["bash", "-c", "gh api user --jq .login"],
                       capture_output=True, text=True, timeout=30)
    return p.returncode == 0, (p.stdout.strip() or p.stderr.strip().splitlines()[-1:] or ["?"])[0] \
        if p.returncode else p.stdout.strip()


def main():
    # 1. hooks registered
    try:
        hooks = json.load(open(SETTINGS)).get("hooks", {})
        got = [e for e in ("SessionStart", "PreToolUse", "PostToolUse")
               if any("secret-guard.py" in h.get("command", "")
                      for g in hooks.get(e, []) for h in g.get("hooks", []))]
        line(len(got) == 3, "secret-guard hooks registered", ", ".join(got) or "none")
    except (OSError, ValueError):
        line(False, "secret-guard hooks registered", f"cannot read {SETTINGS}")

    # 2. token removed from the Bash environment
    leaked = [v for v in ("GH_TOKEN", "GITHUB_TOKEN") if os.environ.get(v)]
    line(not leaked, "GH_TOKEN absent from this shell",
         f"still set: {', '.join(leaked)} (SessionStart hook did not run?)" if leaked else "")

    # 3. token file
    try:
        st = os.stat(TOKEN_FILE)
        token = open(TOKEN_FILE).read()
    except OSError:
        line(False, "token file", "missing: GH_TOKEN is not set on the environment, or the hook did not run")
        return
    mode = stat.S_IMODE(st.st_mode)
    line(mode == 0o600, "token file permissions", oct(mode))
    token = token.rstrip("\n")
    kind, problems = token_shape(token)
    line(not problems and not kind.startswith("UNRECOGNIZED"), "token format",
         f"{kind}, {len(token)} chars" + (f"; PROBLEM: {'; '.join(problems)}" if problems else ""))

    # 4. does gh actually work?
    ok, info = gh_works()
    line(ok, "gh api user", f"authenticated as {info}" if ok else info)

    # 5. gh wrapper in front
    gh = subprocess.run(["bash", "-c", "command -v gh"], capture_output=True, text=True).stdout.strip()
    is_wrapper = bool(gh) and "claude-cloud gh wrapper" in open(gh, errors="ignore").read()
    line(is_wrapper, "gh resolves to the token-injecting wrapper", gh or "gh not found")


if __name__ == "__main__":
    main()
