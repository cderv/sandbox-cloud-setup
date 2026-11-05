#!/usr/bin/env python3
"""cloud-doctor: check this environment's setup WITHOUT printing any secret.

Installed as ~/.local/bin/cloud-doctor by setup.sh. Safe to run from a Claude
session: it reports only whether things are set / registered / working.
"""
import json
import os
import re
import subprocess

SETTINGS = os.path.expanduser("~/.claude/settings.json")
STATE = os.path.expanduser("~/.config/cloud-setup/state")
DEFAULTS = os.path.expanduser("~/.config/cloud-setup/defaults")


def line(ok, label, detail=""):
    print(f"{'OK ' if ok else '!! '} {label}{': ' + detail if detail else ''}")


def read_kv(path):
    out = {}
    try:
        with open(path) as f:
            for raw in f:
                k, _, v = raw.strip().partition("=")
                out[k] = v
    except OSError:
        pass
    return out


def opt(name, defaults):
    """Wanted value of CLOUD_SETUP_<name>, same rule as setup.sh: the
    environment variable when set, else the pasted bootstrap's options block.
    Returns (value, where it came from)."""
    key = f"CLOUD_SETUP_{name}"
    if os.environ.get(key):
        v, src = os.environ[key], "variable"
    elif defaults.get(key):
        v, src = defaults[key], "bootstrap"
    else:
        return "", "unset"
    return ("" if v == "off" else v), src


def version(cmd):
    p = subprocess.run(["bash", "-c", f"{cmd} --version"], capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else "missing"


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
    state = read_kv(STATE)
    defaults = read_kv(DEFAULTS)
    if not state:
        line(False, "setup state", f"{STATE} missing: this environment's setup script never "
             "ran bootstrap.sh (e.g. the Default environment). Paste bootstrap.sh into the "
             "environment's Setup script, then start a new session.")
    line(bool(state.get("rev")), "setup commit",
         f"{state.get('rev', 'none')[:12]} (wanted ref: "
         f"{os.environ.get('CLOUD_SETUP_REF') or state.get('ref') or 'main'})")
    line(bool(defaults), "bootstrap options block",
         "present" if defaults else "none (pasted bootstrap predates it: options only via variables)")
    p = subprocess.run(["bash", "-c", "command -v gh"], capture_output=True, text=True)
    line(p.returncode == 0, "gh", p.stdout.strip() or "missing")

    # 1c. opt-in features (bootstrap options block, or CLOUD_SETUP_* variables)
    moving = ("release", "prerelease", "latest")
    for name, key, cmd in (("BRAID", "braid", "braid"),
                           ("QUARTO", "quarto", "quarto"),
                           ("AGENT_BROWSER", "agent_browser", "agent-browser"),
                           ("JUST", "just", "just")):
        want, src = opt(name, defaults)
        if name == "BRAID":
            want = want.removeprefix("v")
        if not want:
            continue
        got = version(cmd)
        ok = got != "missing" and (want in moving or (got.split() or [""])[-1] == want)
        line(ok and state.get(key) == want, cmd,
             f"{got} (CLOUD_SETUP_{name}={want} from {src}, setup ran with {state.get(key) or 'unset'})")
    if opt("AGENT_BROWSER", defaults)[0]:
        try:
            exe = json.load(open(os.path.expanduser("~/.agent-browser/config.json"))).get("executablePath")
        except (OSError, ValueError):
            exe = None
        line(bool(exe) and os.access(exe, os.X_OK), "agent-browser browser",
             f"{exe} (~/.agent-browser/config.json)" if exe else "no executablePath in ~/.agent-browser/config.json")
        skill = os.path.expanduser("~/.claude/skills/agent-browser/SKILL.md")
        line(os.path.isfile(skill), "agent-browser skill", skill if os.path.isfile(skill) else "missing")
    r, src = opt("R", defaults)
    if r:
        p = subprocess.run(["/usr/local/bin/Rscript", "-e", "cat(format(getRversion()))"],
                           capture_output=True, text=True) if os.path.exists("/usr/local/bin/Rscript") else None
        got = p.stdout.strip() if p and p.returncode == 0 else "missing"
        exact = all(x.isdigit() for x in r.split(".")) and r.count(".") == 2
        ok = got != "missing" and (got == r or not exact)
        line(ok and state.get("r") == r, "R (rig)",
             f"{got} (CLOUD_SETUP_R={r} from {src}, setup ran with {state.get('r') or 'unset'})"
             + ("" if ok else " - R needs Custom network access: api.r-hub.io, cdn.posit.co, ..."))
    uv = os.path.expanduser("~/.local/bin/uv")
    uv = uv if os.path.exists(uv) else "uv"
    u, src = opt("UV", defaults)
    if u:
        p = subprocess.run(["bash", "-c", f"'{uv}' --version"], capture_output=True, text=True)
        got = p.stdout.split()[1] if p.returncode == 0 and len(p.stdout.split()) > 1 else "missing"
        ok = got != "missing" and (u == "latest" or got == u)
        line(ok and state.get("uv") == u, "uv",
             f"{got} (CLOUD_SETUP_UV={u} from {src}, setup ran with {state.get('uv') or 'unset'})")
    py, src = opt("PYTHON", defaults)
    if py:
        missing = [v for v in py.replace(",", " ").split()
                   if subprocess.run(["bash", "-c", f"'{uv}' python find --managed-python '{v}'"],
                                     capture_output=True).returncode != 0]
        line(not missing and state.get("python") == py, "python (uv-managed)",
             (f"missing {' '.join(missing)}" if missing else "all found")
             + f" (CLOUD_SETUP_PYTHON={py} from {src}, setup ran with {state.get('python') or 'unset'})")
    try:
        attribution = json.load(open(SETTINGS)).get("attribution")
    except (OSError, ValueError):
        attribution = None
    keep, src = opt("ATTRIBUTION", defaults)
    keep = keep == "keep"
    line(keep or attribution == {"commit": "", "pr": "", "sessionUrl": False}, "commit/PR attribution",
         f"kept (CLOUD_SETUP_ATTRIBUTION=keep from {src})" if keep else f"settings: {attribution}")

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

    # 3. variables the setup expects (names only, never values)
    if opt("BRAID", defaults)[0]:
        for v in ("BRAID_SYNC_URL", "BRAID_DOC_ID"):
            line(bool(os.environ.get(v)), v, "set" if os.environ.get(v) else "unset")
    names, src = opt("SECRET_VARS", defaults)
    for v in filter(None, re.split(r"[\s,]+", names)):
        line(True, f"secret-guard protects {v}",
             ("set" if os.environ.get(v) else "unset") + f" (from {src})")


if __name__ == "__main__":
    main()
