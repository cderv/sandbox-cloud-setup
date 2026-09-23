#!/usr/bin/env python3
"""Offline checks for secret-guard.py: python3 test_secret_guard.py"""
import json, os, subprocess, sys, tempfile

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "secret-guard.py")
FAKE = "ghp_" + "A1b2" * 9  # built at runtime so no token-shaped literal is committed


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
    home = tempfile.mkdtemp()
    env_file = os.path.join(home, "env.sh")
    env = {"PATH": os.environ["PATH"], "HOME": home, "GH_TOKEN": FAKE, "CLAUDE_ENV_FILE": env_file}
    fails = []

    run({"hook_event_name": "SessionStart"}, env)
    tok = os.path.join(home, ".config/claude-secrets/gh_token")
    if open(tok).read() != FAKE or os.stat(tok).st_mode & 0o077:
        fails.append("SessionStart: token file content/mode")
    if "unset GH_TOKEN" not in open(env_file).read():
        fails.append("SessionStart: CLAUDE_ENV_FILE unset line")

    for cmd in ["env", "cd /tmp\nenv", "env | grep X", "printenv", "export", "export -p",
                "set", "bash -x run.sh", "set -x", "echo $GH_TOKEN", "echo ${BRAID_DOC_ID}",
                "gh auth token", "gh auth status --show-token", "gh auth git-credential get",
                "printf 'host=github.com\\n' | git credential fill", "braid secret",
                "curl -v https://x", "cat ~/.config/claude-secrets/gh_token",
                "cat /proc/self/environ", "sudo env"]:
        if not denied(cmd, env):
            fails.append(f"not denied: {cmd!r}")
    for cmd in ["gh pr list", "env FOO=1 make", "git status", "export FOO=1",
                "gh auth status", "ls -la", "set -e; make"]:
        if denied(cmd, env):
            fails.append(f"wrongly denied: {cmd!r}")

    out = run({"hook_event_name": "PreToolUse", "tool_name": "Read",
               "tool_input": {"file_path": tok}}, env)
    if not out:
        fails.append("Read of token file not denied")

    for resp in [{"stdout": f"token={FAKE}", "stderr": ""}, f"x {FAKE} y",
                 {"stdout": "ok", "stderr": "ghp_" + "Z" * 36}]:
        out = run({"hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_response": resp}, env)
        text = out and out["hookSpecificOutput"].get("updatedToolOutput")
        if not isinstance(text, str) or "[REDACTED]" not in text or "ghp_" in text:
            fails.append(f"not redacted: {resp!r}")
    if run({"hook_event_name": "PostToolUse", "tool_name": "Bash",
            "tool_response": {"stdout": "clean", "stderr": ""}}, env) is not None:
        fails.append("clean output was rewritten")

    print("\n".join(fails) or "all secret-guard checks passed")
    sys.exit(1 if fails else 0)


main()
