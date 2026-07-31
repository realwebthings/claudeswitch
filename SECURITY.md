# Security Policy

claudeswitch copies OAuth credentials between storage slots. That is inherently
sensitive, so this document states exactly what it stores, where, and what leaves
your machine.

## Reporting a vulnerability

Please do **not** open a public issue for anything that could expose credentials.
Use [GitHub's private vulnerability reporting](https://github.com/realwebthings/claudeswitch/security/advisories/new)
instead.

Relevant classes for this tool: a switch leaking a token to a wider-readable
location, slot names escaping their directory, an identity mismatch letting one
account's token be parked under another's name, or command injection through a
slot name.

Only the latest version is patched.

## What it stores, and where

Each parked slot holds a **complete OAuth access + refresh token**. Any one of
them grants full access to that account.

| Platform | Live credential | Parked slots |
| --- | --- | --- |
| macOS | login Keychain, service `Claude Code-credentials` | Keychain, service `Claude Code-credentials-<name>` |
| Linux / WSL / Windows | `~/.claude/.credentials.json` (mode 600) | `~/.claude-accounts/<name>.credentials.json` (mode 600, dir 700) |

Plus, on every platform, the displayed identity — **no token in it** — at
`~/.claude-accounts/<name>.oauthAccount.json`, and a backup of `~/.claude.json`
at `~/.claude.json.claudeswitch.bak`.

**A parked slot gets the same protection the platform already gives the live
credential.** claudeswitch never downgrades storage: Keychain stays Keychain,
mode-600 file stays mode-600. Writes go through a temp file in the same directory
under `umask 077`, then an atomic `mv`, so a token is never briefly world-readable
and an interrupted switch cannot leave a half-written credential.

### The real change: N copies instead of 1

This is the honest tradeoff. Before claudeswitch, one credential existed. After
parking N accounts, N+1 do. Anything that can read the live credential — your own
user account, root, an unlocked Keychain, a process running as you — can now reach
every account you have parked.

On **Linux/WSL/Windows** those parked tokens are plaintext on disk, because that is
how Claude Code stores the live one. Two consequences worth acting on:

- **Backups now contain every parked token.** Exclude `~/.claude-accounts/` if your
  backup destination is less trusted than your disk.
- **Disk encryption is what protects these at rest.** There is no additional
  encryption layer in this tool.

If that tradeoff is unacceptable, use `ANTHROPIC_API_KEY` per terminal instead. It
bypasses the credential store entirely — but usage is billed per token rather than
drawing on a Pro/Team seat, and a key in a settings file is also plaintext.

## Network calls

**One, and only when resolving an account email:**

```
GET https://api.anthropic.com/api/oauth/profile
    Authorization: Bearer <the token being identified>
```

Used by `list`, `whoami`, `save`, and the unparked-account check, because a stored
credential contains no email — the API is the only reliable way to tell accounts
apart (accounts in one organization share an `organizationUuid`). It is a 10-second
timeout, and every caller treats failure as non-fatal: you get
`(lookup failed — offline or token expired)` rather than an error.

Nothing else contacts the network. There is **no telemetry, no analytics, no
crash reporting, no phone-home, and no backend** — there is nothing to send data
to. The tool is a single Bash script plus a hook; the only other binaries it
invokes are `security` (macOS Keychain), `python3` (JSON parsing), and `curl` (that
one request).

The two other URLs in the source are text in error messages — the GitHub repo and
issues links — not requests.

## Installation

claudeswitch **downloads nothing at install time**. It ships as a Claude Code
plugin, so `/plugin install` fetches the repo and that is the whole install. There
is no curl-pipe-to-shell installer, no post-install script, and no fetching of
code from a second location — so there is no download to verify with a checksum.

`claudeswitch install-shim` writes one small forwarder script to a directory on
your PATH (default `~/.local/bin/claudeswitch`). It refuses to overwrite a file
that is not already a claudeswitch shim, and it will not edit your shell profile
without asking. The SessionStart hook deliberately only *reports* that the shim is
missing — a plugin should not add executables to your PATH unasked.

## Deliberate safety behaviors

These exist because a half-applied switch is worse than a failed one:

- **`use` refuses while other Claude Code sessions are running.** A live session
  rewrites the credential on token refresh and would silently revert the switch.
- **`save` refuses when the stored token and `~/.claude.json` name different
  accounts.** That mismatch is what mislabels a slot — parking the wrong account's
  token under a name you trust. This check cannot be forced.
- **`save` refuses to overwrite a slot holding a different account**, which would
  cost that account a `/login`. Requires `CLAUDESWITCH_FORCE=1`.
- **`use` parks the outgoing credential** to `_previous` when it is not already in
  a slot, so switching cannot destroy an unparked account.
- **Auto-parking unrecognized accounts is opt-in**, because it writes a token copy
  to disk without being asked. Default behavior is to warn only.
- **Slot names are validated** against `[A-Za-z0-9._-]` (and rejected if `.` or
  `..`) on every command that takes one — `save`, `use`, and `rm`. On the file
  backend a slot name becomes a path component, so this is what stops a name from
  escaping `~/.claude-accounts`.

## Fixed issues

**Path traversal in `rm` (fixed in 1.8.0).** Slot-name validation was applied only
to `save`, so `claudeswitch rm '../somewhere/file'` deleted
`../somewhere/file.credentials.json` — a file outside the park directory. `use` was
not exploitable (a non-credential file fails to parse and the switch aborts), and
neither path leaked credentials. Exploiting it required the user to run the command
with a crafted argument, so there was no privilege escalation. Validation now runs
on every command that accepts a name, with regression tests.

## Unofficial internals

This tool depends on Claude Code implementation details that are not public API:
the Keychain service name, the credential file path, and the `oauthAccount` key in
`~/.claude.json`. A Claude Code update could rename or relocate any of them.

When that happens, claudeswitch reports what it found and refuses to act rather
than half-applying a switch — but it cannot survive a rename. Treat a surprising
error as "this broke," not "force it through."

## Scope

Windows-native support is best-effort and unverified; if your install keeps
credentials in Windows Credential Manager rather than a file, claudeswitch says so
instead of pretending to switch. WSL is the tested path for Windows.

There is no per-window account isolation: the active credential is global to the
machine, so exactly one account is active at a time.
