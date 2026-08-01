# claudeswitch

**Multiple Claude accounts, one machine. `/login` keeps logging you out of the others.**

Work account for work, personal account for side projects — but Claude Code stores
exactly one credential. Signing into the second account destroys the first, so
switching means a full browser OAuth flow every time.

claudeswitch parks each account in its own slot, so switching is one command:

```bash
claudeswitch save work        # park the account you're signed into (once)
claudeswitch save personal    # park the other one (once)

claudeswitch use work         # switch — no /login, no browser
```

One `/login` per account, ever. `claudeswitch list` shows who's parked and who's
active, with real emails resolved from the API.

**Platforms:** macOS and Linux/WSL are supported and tested. Windows-native is
best-effort — use WSL. [Details below](#platform-support).

**Requires** `curl` only. No python, no node, no dependencies.
**Handles OAuth tokens** — see [SECURITY.md](SECURITY.md) for exactly what is stored where.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/realwebthings/claudeswitch/main/install.sh | bash
```

That's it. The script puts `claudeswitch` in `~/.local/bin` (or wherever is
already on your PATH) and offers to update your shell profile if needed.

**Specific version:**
```bash
curl -fsSL https://raw.githubusercontent.com/realwebthings/claudeswitch/main/install.sh | bash -s -- --version v2.0.5
```

**Manual download** — grab `bin/claudeswitch` from any
[release](https://github.com/realwebthings/claudeswitch/releases), put it
anywhere on your PATH, and `chmod +x` it.

**Update:**
```bash
claudeswitch update
```

---

## Quickstart

```
1. install (above)
2. save, THEN /login, per account   — one login per account, ever
3. claudeswitch use <name>          — claudeswitch handles the rest
```

**Order matters in step 2:** `save` the account you're on *before* running
`/login`, because `/login` overwrites the live credential. Park first and nothing
is ever lost.

---

## Set up each account — one `/login` per account, ever

For each account:

1. **Log in** — Run `/login` in Claude Code (terminal), or use the account UI in
   the VSCode extension.
2. **Park it:**
   ```bash
   claudeswitch save work
   ```
   `save` prints which account it actually parked. Check that line matches what
   you intended before moving on.
3. Repeat for the next account — `/login` as the second account, then
   `claudeswitch save personal`.

Then verify both:

```bash
claudeswitch list
```

```
parked slots:
  personal       you@personal.example
  work           you@company.example

active account:
  account:  you@personal.example
  plan:     team / default_raven
  access:   2026-07-30 23:32
  refresh:  2026-08-28 02:39
```

Slot names are arbitrary labels — use whatever you like.

---

## Daily use

```bash
claudeswitch use work        # switch accounts (prompts to kill Claude Code if running)
claudeswitch list            # who's parked, who's active
claudeswitch whoami          # active account only
claudeswitch save <name>     # re-park after a fresh /login
claudeswitch rm <name>       # delete a parked slot
claudeswitch update          # update to latest version
claudeswitch help            # full help
```

**Switching while Claude Code is running:** `claudeswitch use` detects running
sessions and prompts:

```
claudeswitch: Claude Code is running (pid: 12345).

  ⚠️  WARNING: Killing Claude Code will close all active sessions.
  Any unsaved work or ongoing tasks in Claude Code will be lost.

  Kill it and switch? [y/N]
```

Answer `y` and it kills Claude Code, switches the account, then tells you to
reopen. Answer `n` to cancel. Use `CLAUDESWITCH_FORCE=1` to skip the prompt.

---

## Platform support

| Platform | Status | Credentials are stored in |
| --- | --- | --- |
| macOS | Supported, tested | login Keychain, via `security` |
| Linux | Supported, tested | `~/.claude/.credentials.json` (mode 600) |
| Windows + WSL | Supported — use the Linux path inside your WSL distro | same as Linux |
| Windows native | Best-effort, **not verified** | see below |

The storage backend is detected automatically; override it with
`CLAUDESWITCH_BACKEND=keychain|file` if you need to.

**Windows native:** claudeswitch needs a bash (Git Bash / MSYS) and a Claude Code
install that keeps its token in `.credentials.json` under your user profile. If
your install uses Windows Credential Manager instead, claudeswitch will tell you
so rather than pretend to switch — running Claude Code under WSL is the reliable
option today.

---

## Not losing an account

**`use` parks the outgoing account first.** Switching overwrites the live
credential, so if you were logged in as an account that isn't in a slot, its token
would be gone. Instead it lands in `_previous`:

```
$ claudeswitch use work
  parked outgoing account to '_previous' (recover with: claudeswitch use _previous)
active account = slot 'work'
```

**`save` won't silently clobber a different account.** Re-saving the same account
into its own slot is the normal refresh path and stays quiet, but pointing an
existing slot at a *different* account needs `CLAUDESWITCH_FORCE=1`.

**Park before `/login`:**

```bash
claudeswitch save work     # park the current account FIRST
/login                     # now safe — this overwrites the live credential
claudeswitch save personal
```

---

## How it works

Logging in writes **two** pieces of state. Both must be swapped together.

### 1. OAuth tokens — one credential slot

**macOS** — one login Keychain entry:

```
"Claude Code-credentials"            <- active; Claude Code reads only this
"Claude Code-credentials-work"       <- parked, survives /login
"Claude Code-credentials-personal"   <- parked, survives /login
```

**Linux, WSL, Windows/Git Bash** — one file, `~/.claude/.credentials.json`:

```
~/.claude/.credentials.json                       <- active
~/.claude-accounts/work.credentials.json          <- parked
~/.claude-accounts/personal.credentials.json      <- parked
```

Every write goes to a temp file then `mv`'d into place atomically. Tokens are
written under `umask 077`, parking directory is `700`.

### 2. Displayed identity — `~/.claude.json`

The email shown in the UI comes from an `oauthAccount` key in `~/.claude.json`,
not from the token. `use` rewrites only that key, backs the file up to
`~/.claude.json.claudeswitch.bak`, and replaces atomically.

---

## Separate settings per account (optional)

```bash
cp -R ~/.claude/plugins ~/.claude-work/plugins   # independent copy
```

Launcher functions in `~/.zshrc`:

```bash
_claude_as() {
  local slot="$1" email="$2" cfg="$3"; shift 3
  local current
  current="$(claudeswitch whoami 2>/dev/null | grep 'account:' | sed 's/.*account:[[:space:]]*//')"
  if [ "$current" != "$email" ]; then
    claudeswitch use "$slot" || return 1
  fi
  CLAUDE_CONFIG_DIR="$cfg" claude "$@"
}

function claude-work     { _claude_as work     you@company.example  "$HOME/.claude-work" "$@"; }
function claude-personal { _claude_as personal you@personal.example "$HOME/.claude"      "$@"; }
```

Use `function name { }` not `name() { }` — zsh rejects the parenthesis form for
hyphenated names in an interactive shell.

---

## Security

Each parked slot holds a full OAuth access + refresh token. Any one of them
grants complete access to that account.

A parked slot gets **the same protection Claude Code already gives the live
credential on that platform**. The real change is **N token copies instead of 1**.

- **macOS** — parked in your login Keychain. Nothing written to disk in plaintext.
- **Linux / WSL / Windows** — mode 600 files in a `700` directory, same as the
  live credential. If you back up your home directory, **your backups now contain
  N tokens** — exclude `~/.claude-accounts/` if that matters.

See [SECURITY.md](SECURITY.md) for the full threat model.

---

## Troubleshooting

**`refusing to save — the active state is inconsistent`**
The token and `~/.claude.json` name different accounts — a session refreshed the
token mid-operation. Quit Claude Code, `/login` as the intended account, retry.

**Switched, but the old email still shows**
Reopen Claude Code. If it persists, that slot has no parked identity — run
`claudeswitch save <name>` again while logged in as that account.

**`(lookup failed — offline or token expired)`**
`list` resolves emails via an API call. Either offline, or that slot's refresh
token expired. Fix: `/login` as that account, then `claudeswitch save <name>`.

**`command not found: claudeswitch`**
Run `source ~/.zshrc` (or open a new terminal) — the PATH change hasn't been
picked up yet. The full path always works: `~/.local/bin/claudeswitch`.

**Keychain permission prompts** (macOS)
macOS asking about the `security` command. Choose "Always Allow".

**`no credential file at ~/.claude/.credentials.json`** (Linux/WSL/Windows)
Open Claude Code and `/login` first. On native Windows this likely means your
install uses Credential Manager — run Claude Code under WSL instead.

**Wrong backend detected**
Force it: `CLAUDESWITCH_BACKEND=file` or `CLAUDESWITCH_BACKEND=keychain`.

---

## Token expiry

Access tokens last hours; refresh tokens roughly a month. Active use rolls the
refresh token forward indefinitely.

An account left idle past its refresh expiry needs one `/login`, then
`claudeswitch save <name>` to re-park it. `claudeswitch list` shows the dates.

---

## Caveats

This depends on unofficial internals: the Keychain service name
`Claude Code-credentials` on macOS, `.credentials.json` inside the config dir
elsewhere, and the `oauthAccount` key in `~/.claude.json`. None is public API.
A Claude Code update could rename or relocate any of them — the script checks
what it finds and refuses to act on surprises rather than half-applying a switch.

There is no true per-window account isolation: one account is active at a time.

---

## Testing

```bash
./test/run-docker.sh              # 4 distros + shellcheck
./test/run-docker.sh alpine       # one distro
./test/run-docker.sh shellcheck   # lint only
```

---

## License

MIT
