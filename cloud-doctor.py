#!/usr/bin/env python3
"""cloud-doctor: check this environment's setup WITHOUT printing any secret.

Installed as ~/.local/bin/cloud-doctor by setup.sh. Safe to run from a Claude
session: it reports only whether things are set / registered / working.
"""
import json
import os
import subprocess

SETTINGS = os.path.expanduser("~/.claude/settings.json")
STATE = os.path.expanduser("~/.config/cloud-setup/state")


def line(ok, label, detail=""):
    print(f"{'OK ' if ok else '!! '} {label}{': ' + detail if detail else ''}")


def main():
    # 1. secret-guard hooks registered
    try:
        hooks = json.load(open(SETTINGS)).get("hooks", {})
        got = [e for e, groups in hooks.items()
               if any("secret-guard.py" in h.get("command", "")
                      for g in groups for h in g.get("hooks", []))]
        want = {"PreToolUse", "PostToolUse"}
        line(want <= set(got), "secret-guard hooks registered", ", ".join(sorted(got)) or "none")
        stale = set(got) - want
        if stale:
            line(False, "stale secret-guard entries", ", ".join(sorted(stale)) + " (re-run setup.sh)")
        start = [g.get("matcher", "") for g in hooks.get("SessionStart", [])
                 if any("cloud-setup-session-start.sh" in h.get("command", "")
                        for h in g.get("hooks", []))]
        line(bool(start), "session-start hook registered", ", ".join(start) or "none")
    except (OSError, ValueError):
        line(False, "secret-guard hooks registered", f"cannot read {SETTINGS}")

    # 1b. installed commit + expected tools (recorded by setup.sh)
    state = {}
    try:
        with open(STATE) as f:
            for raw in f:
                k, _, v = raw.strip().partition("=")
                state[k] = v
    except OSError:
        pass
    line(bool(state.get("rev")), "setup commit",
         f"{state.get('rev', 'none')[:12]} (wanted ref: {os.environ.get('CLOUD_SETUP_REF', 'main')})")
    p = subprocess.run(["bash", "-c", "braid --version"], capture_output=True, text=True)
    got = p.stdout.strip() if p.returncode == 0 else "missing"
    want = state.get("braid", "")
    line(bool(want) and want in got, "braid", f"{got} (expected {want or '?'})")
    p = subprocess.run(["bash", "-c", "command -v gh"], capture_output=True, text=True)
    line(p.returncode == 0, "gh", p.stdout.strip() or "missing")

    # 2. GitHub: no personal token in the environment, handled by the proxy
    for v in ("GH_TOKEN", "GITHUB_TOKEN"):
        val = os.environ.get(v)
        if val and val != "proxy-injected":
            line(False, v, "a real token is set on the environment: it gives no extra access "
                           "(the GitHub proxy decides) and anyone using the environment can read it - remove it")
        else:
            line(True, v, "unset" if val is None else "proxy-injected (GitHub proxy authenticates gh)")

    p = subprocess.run(["bash", "-c", "gh api user --jq .login"],
                       capture_output=True, text=True, timeout=30)
    line(p.returncode == 0, "gh api user",
         f"authenticated as {p.stdout.strip()}" if p.returncode == 0
         else ((p.stderr.strip().splitlines() or ["failed"])[-1]))

    # 3. other environment variables the setup expects (names only)
    for v in ("BRAID_SYNC_URL", "BRAID_DOC_ID"):
        line(bool(os.environ.get(v)), v, "set" if os.environ.get(v) else "unset")


if __name__ == "__main__":
    main()
