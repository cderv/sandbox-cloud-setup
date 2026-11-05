# agent-browser

[agent-browser](https://github.com/vercel-labs/agent-browser) (Vercel Labs,
Apache-2.0) is a browser automation CLI built for agents. It is a native
Rust binary that drives Chrome over CDP and keeps a browser daemon between
commands:

```bash
agent-browser open https://github.com
agent-browser snapshot -i        # accessibility tree, elements as @e1, @e2, ...
agent-browser click @e3
agent-browser fill @e5 "text"
agent-browser screenshot page.png
agent-browser close
```

Turn it on with `CLOUD_SETUP_AGENT_BROWSER="latest"` (or an exact version) in
the [options block](options.md).

## What setup does

1. Installs the npm package `agent-browser@<version>` into
   `/opt/agent-browser/<version>` (`npm install -g --prefix`), linked as
   `~/.local/bin/agent-browser`. `latest` is resolved with
   `npm view agent-browser version`.
2. Points it at the image's **pre-installed Playwright Chromium**
   (`/opt/pw-browsers/chromium`) by writing `executablePath` to
   `~/.agent-browser/config.json`. A path you set there yourself is kept
   while it points at a working executable. Without Chromium (another image,
   or CI), it falls back to `google-chrome`/`chromium` on `PATH`, then to
   `agent-browser install`.
3. Copies the package's discovery skill to
   `~/.claude/skills/agent-browser/SKILL.md`. The skill tells Claude to load
   the real guide with `agent-browser skills get core`, which the installed
   CLI serves, so the instructions always match the installed version.

`cloud-doctor` checks the version, the browser path and the skill.

## Browser and network

- **No browser download needed.** `agent-browser install` downloads Chrome
  for Testing from a CDN (`googlechromelabs.github.io`,
  `storage.googleapis.com`) that is not on the Trusted list. You could allow
  those domains with Custom network access, but the image's Chromium is
  enough: `agent-browser doctor` passes its launch test. Its "Chrome for
  Testing CDN unreachable" line is expected and harmless.
- **The network level decides which sites it can open.** The browser goes
  through the session proxy like everything else. Under **Trusted**, a site
  off the allowlist fails with `net::ERR_TUNNEL_CONNECTION_FAILED`
  (`example.com` does). Add the sites you need under **Custom**, or use
  **Full**.
- **HTTPS works through the proxy.** The proxy re-signs TLS, and Chromium
  trusts it because the platform puts its CA in `~/.pki/nssdb` at session
  start. A run under another `HOME` gets `ERR_CERT_AUTHORITY_INVALID`.
- Some sites answer automated browsers with a challenge page (pypi.org
  shows "Client Challenge").

## Notes

- Pin a version with `CLOUD_SETUP_AGENT_BROWSER="0.41.2"` if you want
  reproducible sessions; `latest` moves when the cache is rebuilt.
- The package declares `engines.node >= 24` but ships native binaries, so it
  works with the image's Node 22 (npm only warns `EBADENGINE`). A plain
  `npm install -g agent-browser` on Node 22 was seen resolving an old
  version (0.27.0); setup always installs an explicit version for that
  reason.
- Its socket path must stay under ~103 bytes, which a very long `HOME` can
  exceed. Not a problem with `HOME=/root`.
- Credentials: agent-browser has its own auth vault and session state files
  (`~/.agent-browser/`). State files hold cookies in plaintext; don't commit
  them.
