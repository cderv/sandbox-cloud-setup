# GitHub in the sandbox

## No token needed (or possible)

In Anthropic-hosted environments, **every GitHub request goes through the
platform's GitHub proxy**, whatever the network access level
([docs](https://code.claude.com/docs/en/cloud-environments#github-proxy)):

- **The proxy authenticates for you.** Leave `GH_TOKEN` unset. It then reads
  as the placeholder `proxy-injected`, and `gh`/git just work. Your real
  credentials never enter the VM.
- **Only repositories attached to the session are reachable** through the
  API. Pick them when starting the session, or ask Claude to attach one. A
  token you set yourself doesn't widen this: it only sits readable in the
  environment. So don't set `GH_TOKEN`; the session-start hook and
  `cloud-doctor` warn if a real one is set.
- **GraphQL is refused.** `gh pr view`, `gh issue list` and other GraphQL
  subcommands fail with a 403. Use REST: `gh api repos/OWNER/REPO/issues`.
  APIs that exist only in GraphQL (Projects v2) are out of reach.
- **Pushes**: branch pushes only. The proxy rejects tag pushes and branch
  deletions. It does not restrict *which* branch is pushed; use branch
  protection on GitHub for that.
- **Public repos you can't attach** (e.g. the upstream of a fork):
  `git clone`/`fetch` works, the API does not. To read an issue, give Claude
  its URL: Claude's web fetch runs outside the sandbox.

Don't judge GitHub access by `gh auth status`: behind the proxy it can report
the token "invalid" while real calls work. `cloud-doctor` makes a real call
(`gh api user`) instead.

## Branch names

A cloud session works on a branch it names itself, `claude/<words>-<suffix>`
(e.g. `claude/fix-readme-typo-k2x9pq`). **There is no documented setting
for that name or its prefix** (checked 2026-11-04). What you can do:

- **Ask in the session**: "push to branch `feature/x`". The session is told
  to stay on its branch unless you explicitly allow another one, so say it
  explicitly. The proxy accepts any branch name.
- **Continue an existing branch**: start the session from that branch, or ask
  Claude to check it out and push there.
- **Sessions started by another session** (orchestration): the
  `create_session` tool takes an `outcome_branch` that is used as is, with no
  suffix.
- **After the fact**: rename the branch on GitHub, or open the PR from
  whatever branch it is on.

## Contributing to someone else's repo

Start the session on your fork, add `upstream` as a git remote, hand Claude
the issue URL, and open the PR from your fork on GitHub.
