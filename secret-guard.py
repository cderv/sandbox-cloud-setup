#!/usr/bin/env python3
"""
Claude Code hook: keep secrets (GH_TOKEN, BRAID_DOC_ID, ...) out of the model's
context. Installed by setup.sh; one script, dispatched on hook_event_name:

  SessionStart  -> copy GH_TOKEN to a 600 file (refreshed every session, so a
                   rotated token is picked up even though the setup script is
                   cached), then unset GH_TOKEN/GITHUB_TOKEN for every Bash tool
                   command via $CLAUDE_ENV_FILE. `gh` reads the file through its
                   wrapper.
  PreToolUse    -> deny commands/reads that would dump a secret
                   (xtrace, env dumps, `gh auth token`, `braid secret`, ...).
  PostToolUse   -> if a secret value or GitHub token pattern shows up in a tool
                   output, replace the output (updatedToolOutput) with a
                   redacted copy before Claude sees it.

Fails open on its own errors (never breaks a tool call). This stops accidental
leaks into the transcript; it is not a sandbox. Keep tokens fine-grained,
repo-scoped and short-lived.
"""
import json
import os
import re
import sys

SECRET_VARS = ("GH_TOKEN", "GITHUB_TOKEN", "BRAID_DOC_ID")
SECRETS_DIR = os.path.expanduser("~/.config/claude-secrets")
TOKEN_FILE = os.path.join(SECRETS_DIR, "gh_token")

# GitHub token formats: classic/OAuth/user/server/refresh + fine-grained PATs.
TOKEN_RE = re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b")

SECRET_PATHS = r"(?:claude-secrets|\.config/gh/hosts\.yml|\.braid\.toml|\.git-credentials)"
# Start of a shell command: start of a line, after a separator, or after sudo.
CMD_START = r"(?:^|[;&|(\n]\s*|\bsudo\s+)"
DENY_BASH = [
    (r"(?:^|[\s;&|(])(?:ba|z|da|k)?sh\s+(?:-\w*x|-o\s+xtrace)\b|\bset\s+(?:-\w*x\w*|-o\s+xtrace)\b|\bBASH_XTRACEFD\b",
     "xtrace (bash -x / set -x) echoes expanded commands and can print secrets"),
    (CMD_START + r"(?:env|printenv|export|export\s+-p|declare\s+-\w*[px]\w*|typeset\s+-\w*p\w*|set|compgen\s+-v)\s*(?:$|[|;&>)])",
     "dumping the whole environment would print secrets"),
    (r"\bprintenv\s+\w*(?:TOKEN|SECRET|DOC_ID|PASSWORD|KEY)\b",
     "printing a secret environment variable"),
    (r"\$\{?!?(?:" + "|".join(SECRET_VARS) + r")\b",
     "referencing a secret variable in a command; use the tool that needs it (gh, braid) instead"),
    (r"/proc/[^\s]*/environ", "reading a process environment would print secrets"),
    (r"\bgh\s+auth\s+(?:token|git-credential|status\b.*(?:-t\b|--show-token))", "prints the GitHub token"),
    (r"\bgit\s+credential\s+fill\b|\bgit\s+credential-\w+\s+get\b", "prints stored git credentials"),
    (r"\bbraid\s+secret\b", "prints the braid doc id (bearer secret); ask the user to run it"),
    (r"\bcurl\b.*\s(?:-v\b|--verbose\b|--trace)", "curl verbose/trace output includes auth headers"),
    (SECRET_PATHS, "this path holds a secret"),
]
DENY_BASH = [(re.compile(p, re.M), reason) for p, reason in DENY_BASH]
DENY_PATH = re.compile(SECRET_PATHS)


def secret_values():
    vals = {os.environ.get(v, "") for v in SECRET_VARS}
    try:
        with open(TOKEN_FILE) as f:
            vals.add(f.read().strip())
    except OSError:
        pass
    return sorted((v for v in vals if len(v) >= 12), key=len, reverse=True)


def redact(obj, values):
    if isinstance(obj, str):
        for v in values:
            obj = obj.replace(v, "[REDACTED]")
        return TOKEN_RE.sub("[REDACTED]", obj)
    if isinstance(obj, list):
        return [redact(x, values) for x in obj]
    if isinstance(obj, dict):
        return {k: redact(x, values) for k, x in obj.items()}
    return obj


def as_text(resp):
    """updatedToolOutput is a string: flatten the (already redacted) response."""
    if isinstance(resp, str):
        return resp
    if isinstance(resp, dict) and ("stdout" in resp or "stderr" in resp):
        out, err = resp.get("stdout") or "", resp.get("stderr") or ""
        return out + ("\n" + err if out and err else err)
    return json.dumps(resp, indent=2)


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": f"secret-guard: {reason}. Blocked to keep secrets out of the transcript.",
    }}))


def session_start():
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        os.makedirs(SECRETS_DIR, mode=0o700, exist_ok=True)
        os.chmod(SECRETS_DIR, 0o700)
        fd = os.open(TOKEN_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(token)
    env_file = os.environ.get("CLAUDE_ENV_FILE")
    if env_file:
        with open(env_file, "a") as f:
            f.write("unset GH_TOKEN GITHUB_TOKEN\n")


def pre_tool_use(data):
    tool, inp = data.get("tool_name", ""), data.get("tool_input") or {}
    if tool == "Bash":
        cmd = inp.get("command", "")
        for pattern, reason in DENY_BASH:
            if pattern.search(cmd):
                return deny(reason)
    else:
        target = " ".join(str(inp.get(k, "")) for k in ("file_path", "path", "pattern", "notebook_path"))
        if DENY_PATH.search(target):
            return deny("this path holds a secret")


def post_tool_use(data):
    resp = data.get("tool_response")
    clean = redact(resp, secret_values())
    if clean != resp:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "updatedToolOutput": as_text(clean),
            },
            "systemMessage": "secret-guard: redacted a secret from a tool output",
        }))


def main():
    data = json.load(sys.stdin)
    event = data.get("hook_event_name")
    if event == "SessionStart":
        session_start()
    elif event == "PreToolUse":
        pre_tool_use(data)
    elif event == "PostToolUse":
        post_tool_use(data)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # never break the session because of the guard itself
        print(f"secret-guard error: {e}", file=sys.stderr)
