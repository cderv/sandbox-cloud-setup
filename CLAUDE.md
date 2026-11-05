# Working on this repo

**This repository is public.** Everything committed here, files *and* git
history (commit messages, trailers, branch names), is visible to anyone.

- Never commit secrets, tokens, private URLs (relay/sync servers, doc IDs),
  or session links.
- Never commit anything personal: names of private projects, talks, clients,
  environments, machines, branches or sessions. Invent neutral examples
  (`feature/x`, `https://github.com/OWNER/REPO`, `MY_API_KEY`).
- Commits and PRs carry **no** `Co-Authored-By` trailer and **no**
  `Claude-Session:` link (`.claude/settings.json` sets `attribution` off).
- Anything a user would want to change (repo URL, tools, versions, secret
  variable names) must be an option, not hardcoded: see `docs/options.md`.
  Only variable *names* go in files, never values.
- The setup script cannot read environment variables; options come from the
  bootstrap's options block or are read later by the session-start hook. See
  `docs/how-it-works.md`.

Before committing, run:

```bash
python3 test_secret_guard.py
```

```bash
shellcheck -S warning *.sh
```

and check the diff for anything personal.
