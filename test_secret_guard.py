#!/usr/bin/env python3
"""Offline checks for secret-guard.py: python3 test_secret_guard.py"""
import json, os, subprocess, sys

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "secret-guard.py")
FAKE_GH = "ghp_" + "A1b2" * 9          # built at runtime: no token-shaped literal committed
FAKE_DOC = "automerge:" + "Zq9" * 8     # stands in for BRAID_DOC_ID


def run(payload, env):
    p = subprocess.run([sys.executable, HOOK], input=json.dumps(payload),
                       capture_output=True, text=True, env=env)
    assert p.returncode == 0 and not p.stderr, p.stderr
    return json.loads(p.stdout) if p.stdout.strip() else None


def denied(cmd, env):
    out = run({"hook_event_name": "PreToolUse", "tool_name": "Bash",
               "tool_input": {"command": cmd}}, env)
    return bool(out) and out["hookSpecificOutput"]["permissionDecision"] == "deny"


def main():
    env = {"PATH": os.environ["PATH"], "HOME": "/nonexistent", "BRAID_DOC_ID": FAKE_DOC,
           "GH_TOKEN": "proxy-injected"}
    fails = []

    for cmd in ["env", "cd /tmp\nenv", "env | grep X", "printenv", "export", "export -p",
                "set", "bash -x run.sh", "set -x", "echo $BRAID_DOC_ID", "echo ${BRAID_DOC_ID}",
                "printenv BRAID_DOC_ID", "gh auth token", "gh auth status --show-token",
                "gh auth git-credential get",
                "printf 'host=github.com\\n' | git credential fill", "braid secret",
                "curl -v https://x", "cat ~/.git-credentials", "cat ~/.braid.toml",
                "cat /proc/self/environ", "sudo env"]:
        if not denied(cmd, env):
            fails.append(f"not denied: {cmd!r}")
    for cmd in ["gh pr list", "gh api repos/o/r/issues", "env FOO=1 make", "git status",
                "export FOO=1", "gh auth status", "echo $GH_TOKEN", "ls -la", "set -e; make"]:
        if denied(cmd, env):
            fails.append(f"wrongly denied: {cmd!r}")

    out = run({"hook_event_name": "PreToolUse", "tool_name": "Read",
               "tool_input": {"file_path": "/root/.braid.toml"}}, env)
    if not out:
        fails.append("Read of ~/.braid.toml not denied")

    for resp in [{"stdout": f"doc={FAKE_DOC}", "stderr": ""}, f"x {FAKE_GH} y",
                 {"stdout": "ok", "stderr": "ghp_" + "Z" * 36}]:
        out = run({"hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_response": resp}, env)
        text = out and out["hookSpecificOutput"].get("updatedToolOutput")
        if (not isinstance(text, str) or "[REDACTED]" not in text
                or "ghp_" in text or FAKE_DOC in text):
            fails.append(f"not redacted: {resp!r}")
    for clean in [{"stdout": "clean", "stderr": ""}, {"stdout": "GH_TOKEN=proxy-injected", "stderr": ""}]:
        if run({"hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_response": clean}, env) is not None:
            fails.append(f"clean output was rewritten: {clean!r}")

    print("\n".join(fails) or "all secret-guard checks passed")
    sys.exit(1 if fails else 0)


main()
