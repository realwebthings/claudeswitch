# claudeswitch

Switch between multiple Claude Code accounts on one Mac without re-running
`/login` every time.

**macOS only.** Requires `python3` and `curl` (both preinstalled).

---

## Quickstart

Four steps. Details for each are below.

```
1. install the plugin        /plugin install (or claude plugin install)
2. claudeswitch install-shim   makes the command work outside Claude Code
3. /login + save, per account  one login per account, ever
4. claudeswitch use <name>     switch, then restart Claude Code
```

**Stuck at any point?** Run `/claudeswitch:help` inside Claude Code. It reads
your actual state and tells you the specific cause — faster than matching a
symptom against this page.

---

## 1. Install

Inside Claude Code:

```
/plugin marketplace add https://github.com/realwebthings/claudeswitch
/plugin install claudeswitch
```

**If `/plugin isn't available in this environment`** — some hosts, including the
VSCode extension, don't expose it. Use a terminal instead:

```bash
claude plugin marketplace add https://github.com/realwebthings/claudeswitch
claude plugin install claudeswitch@claudeswitch
```

The `@claudeswitch` suffix is the marketplace name. The CLI requires it; a bare
name fails with `Plugin "claudeswitch" not found`.

This adds the `claudeswitch` command plus two skills:
`/claudeswitch:switch-account` and `/claudeswitch:help`.

## 2. Install the shim

```bash
claudeswitch install-shim
```

Run this once, from inside Claude Code. Without it the command vanishes exactly
when you need it:

```bash
# Claude Code quit — which switching requires:
claudeswitch use work
# zsh: command not found: claudeswitch
```

A plugin's `bin/` is only on PATH inside Claude Code sessions, but `use` needs
Claude Code **quit**. The shim is a small forwarder that locates whatever plugin
version is installed, so it survives updates.

It picks a directory already on your PATH — `~/.local/bin`, `~/bin`, or
`/usr/local/bin`, in that order — so a new terminal just works. If none of them
is on your PATH it installs to `~/.local/bin` and offers to add the line to your
shell profile. Pass a directory to override (`claudeswitch install-shim ~/bin`).

**If the command is still not found**, the shell you're in predates the PATH
change. Run `source ~/.zshrc`, or open a new terminal. `install-shim` detects
this case and says so rather than adding a duplicate line.

The plugin reminds you about this once but won't create it for you:
`~/.local/bin` is outside plugin-managed space, and a plugin shouldn't silently
add executables to your PATH.

---

## 3. Set up each account — one `/login` per account, ever

The `claude` CLI is **not** required — the extension or desktop app is fine.
Only a terminal is needed, to run `claudeswitch` itself.

**Two of these steps only you can do.** Logging in is a browser OAuth flow, and
nothing can quit the session it is running inside. Claude can run the
`claudeswitch` commands for you, but not steps 1 and 2.

For each account:

1. **Log in as it** — *you.* Run `/login` in Claude Code. If your host reports
   `/login isn't available in this environment` (the VSCode extension does), use
   its own account UI, or run `claude` in a terminal and `/login` there.
2. **Quit Claude Code completely** — *you.* Include any extension sidebar.
   Verify:
   ```bash
   pgrep -fl 'native-binary/claude|Claude\.app' # expect no output
   ```
   Orphans can be cleared with `pkill -f 'native-binary/claude'`.
3. **Park it** — *you or Claude.* From a terminal:
   ```bash
   claudeswitch save work
   ```
   `save` prints which account it actually parked. Check that line matches what
   you intended before moving on.

Repeat for the next account, then check both:

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

## 4. Daily use

```bash
claudeswitch use work        # switch, then restart Claude Code
claudeswitch list            # who's parked, who's active
claudeswitch whoami          # active account only
claudeswitch save <name>     # re-park after a fresh /login
claudeswitch rm <name>       # delete a parked slot
claudeswitch install-shim    # make the command work outside Claude Code
```

Or ask Claude: *"switch to my work account"*, *"which account am I on?"*

**Stuck?** Run `/claudeswitch:help` inside Claude Code. It collects the actual
state (parked slots, active account, running sessions, missing identity files)
and walks you through the specific cause — rather than making you match your
symptom against this README.

**Restart Claude Code after switching.** A running session has already read the
credential. For the VSCode sidebar, reload the window.

---

## Updating

Inside Claude Code:

```
/plugin marketplace update claudeswitch
/plugin update claudeswitch
```

Or from a terminal, if `/plugin` isn't available in your host:

```bash
claude plugin marketplace update claudeswitch
claude plugin update claudeswitch@claudeswitch
```

Then **reload the window** (or restart Claude Code) to apply. Until you do, the
session keeps running the previously cached version — the plugin says so on
startup when it detects this.

Old version directories are left behind under
`~/.claude/plugins/cache/claudeswitch/`. Harmless (the shim always picks the
newest) but safe to delete.

The plugin never updates itself. That would let this repo push code onto your
machine without you opting in.

### Multiple config dirs

Plugin registration is per `CLAUDE_CONFIG_DIR` and nothing propagates between
them. If you use several config dirs, install in a session using each one. The
shim handles this itself — it checks `$CLAUDE_CONFIG_DIR` first, then falls back
to `~/.claude`.

---

## The one rule: quit Claude Code before switching

A running session owns the active credential and rewrites it whenever its token
refreshes. Switch while a session is alive and it silently reverts.

| command | with other sessions running |
|---|---|
| `use` | **refuses** — a live session would revert the switch |
| `save` | warns, proceeds if the active state is self-consistent |
| `list` / `whoami` | always safe, read-only |

Both ignore the session *hosting* them, so running from inside a Claude Code
terminal is fine — only other sessions count.

`use` can be forced with `CLAUDESWITCH_FORCE=1` if you know the other session is
idle. `save` has a stronger check that cannot be forced: it compares the
Keychain token against `~/.claude.json` and aborts if they disagree, because
that mismatch is what corrupts a slot.

---

## How it works

Logging in writes **two** pieces of state. Both must be swapped together.

### 1. OAuth tokens — one Keychain entry

```
service = "Claude Code-credentials"
account = <your macOS username>
```

`/login` overwrites it, destroying whichever account was there. There's no
supported way to point Claude Code at a different slot name, so this tool parks
copies under names Claude Code doesn't read:

```
"Claude Code-credentials"            <- active; Claude Code reads only this
"Claude Code-credentials-work"       <- parked, survives /login
"Claude Code-credentials-personal"   <- parked, survives /login
```

### 2. Displayed identity — `~/.claude.json`

The email shown in the UI comes from an `oauthAccount` key in `~/.claude.json`,
not from the token. Swap only the token and the UI keeps showing the previous
email while requests authenticate as the new account.

Note the path: `~/.claude.json`, **not** `~/.claude/`. It sits outside every
config dir. Parked identities live in
`~/.claude-accounts/<name>.oauthAccount.json`.

That file also holds project history and MCP state, so `use` rewrites only the
one key, backs the file up to `~/.claude.json.claudeswitch.bak`, and replaces
atomically.

### Why `CLAUDE_CONFIG_DIR` isn't enough

That env var swaps settings, plugins, and history. It does **not** scope the
Keychain or `~/.claude.json` — every config dir shares both. It's useful
alongside this tool (separate settings per account) but cannot switch accounts
on its own.

---

## Separate settings per account (optional)

```bash
cp -R ~/.claude/plugins ~/.claude-work/plugins   # independent copy
```

Then launcher functions in `~/.zshrc` that switch the account *and* the config
dir together:

```bash
_claude_as() {
  local slot="$1" email="$2" cfg="$3"; shift 3
  local current
  current="$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/.claude.json"))).get("oauthAccount",{}).get("emailAddress",""))' 2>/dev/null)"
  if [ "$current" != "$email" ]; then
    claudeswitch use "$slot" || return 1
  fi
  CLAUDE_CONFIG_DIR="$cfg" claude "$@"
}

function claude-work     { _claude_as work     you@company.example  "$HOME/.claude-work" "$@"; }
function claude-personal { _claude_as personal you@personal.example "$HOME/.claude"      "$@"; }
```

Two details worth copying exactly:

- **Functions, not aliases.** An alias chained with `&&` launches nothing
  whenever `use` refuses — the normal case with a session already open. The
  function skips the switch when the account is already active, so it launches.
- **`function name { }`, not `name() { }`.** zsh rejects the parenthesis form for
  hyphenated names in an interactive shell (`parse error near '()'`). `zsh -n`
  does not catch this; test with `zsh -i -c 'type claude-work'`.

---

## Security

Each parked slot holds a full OAuth access + refresh token. Any one of them
grants complete access to that account.

They live in your login Keychain with the same protection as the credential
Claude Code already stores — nothing is written to disk in plaintext. The real
change is **N token copies instead of 1**: anything that can read your unlocked
login Keychain now finds every account you've parked.

If that's not acceptable, use `ANTHROPIC_API_KEY` per terminal instead. That
bypasses the Keychain entirely, but usage is billed per token rather than drawing
on a Pro/Team seat, and a key in a settings file is plaintext on disk.

---

## Troubleshooting

**Fastest route: run `/claudeswitch:help` inside Claude Code.** It collects your
real state — parked slots and their true emails, running sessions, missing
identity files — and names the specific cause. The entries below are the same
ground, if you'd rather read.

**`/login isn't available in this environment`**
Same host limitation as `/plugin`. Use the extension's own account UI, or run
`claude` in a terminal and `/login` there.

**Can Claude do the switching for me?**
Partly. `list`, `whoami`, and `save` are ordinary commands it can run. `/login`
is a browser flow only you can complete, and `use` has to run with Claude Code
quit — so it cannot be run from inside a session. Ask Claude for those two and it
will tell you the same thing.

**`/plugin isn't available in this environment`**
Some hosts, including the VSCode extension, don't expose `/plugin`. Use the
terminal form: `claude plugin install claudeswitch@claudeswitch` (the
`@marketplace` suffix is required).

**`Plugin "claudeswitch" not found` from the CLI**
Bare names don't resolve. Use `claudeswitch@claudeswitch`.

**`refusing to switch — other Claude Code sessions are running`**
Expected. Quit them and retry. Listed PIDs exclude the session running the
command, so anything shown is genuinely separate — usually a forgotten VSCode
sidebar chat.

**`refusing to save — the active state is inconsistent`**
The Keychain token and `~/.claude.json` name different accounts, because a
session refreshed the token mid-operation. Quit Claude Code, `/login` as the
account you want to park, retry.

**Switched, but the old email still shows**
Restart the session; reload the window for the sidebar. If it persists, that
slot has no parked identity — check `ls ~/.claude-accounts/`. A missing
`<name>.oauthAccount.json` means the token switches but the displayed email
doesn't. Log in as that account and `claudeswitch save <name>` again.

**A slot holds the wrong account's token**
Usually from running `save` while a session was live. `claudeswitch list` shows
the real email per slot. Quit Claude Code, log in as the correct account, re-run
`save`.

**`(lookup failed — offline or token expired)`**
`list` resolves emails via an API call. Offline, or that slot's refresh token
expired. The stored credential holds no email itself.

**`command not found: claudeswitch` even after install-shim**
The shell you're in started before the PATH change. Run `source ~/.zshrc` or open
a new terminal. Re-running `install-shim` will tell you which case you're in. The
full path always works: `~/.local/bin/claudeswitch`.

**`command not found: claudeswitch` in a plain terminal**
Expected before running `claudeswitch install-shim`. A plugin's `bin/` is only on
PATH inside Claude Code sessions. Run `install-shim` once from inside Claude Code,
then the command works anywhere. If it still isn't found afterwards, the shim
directory isn't on your PATH — `install-shim` prints the line to add.

**Keychain permission prompts**
macOS asking about the `security` command. Choose "Always Allow".

---

## Token expiry

Access tokens last hours; refresh tokens roughly a month. Active use rolls the
refresh token forward, so an account you use regularly stays logged in
indefinitely.

An account left idle past its refresh expiry needs one `/login`, then
`claudeswitch save <name>` to re-park it. `claudeswitch list` shows the dates.

Server-side. No local setup avoids it.

---

## Caveats

This depends on two unofficial internals: the Keychain service name
`Claude Code-credentials`, and the `oauthAccount` key in `~/.claude.json`.
Neither is public API. A Claude Code update could rename or relocate either, in
which case this breaks — the script checks what it finds and refuses to act on
surprises rather than half-applying a switch, but it cannot survive a rename.

The VSCode extension sidebar always uses `~/.claude` settings regardless of
account, since it ignores `CLAUDE_CONFIG_DIR`. Only the active credential
follows a switch there.

There is no true per-window account isolation: the active Keychain slot is
global to the machine. One account is active at a time.

---

## License

MIT
# claudeswitch
# claudeswitch
