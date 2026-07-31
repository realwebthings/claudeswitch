# claudeswitch

**Two Claude accounts, one machine. `/login` keeps logging you out of the other
one.**

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
active, with real emails resolved from the API — not just the labels you chose.

Stuck? `/claudeswitch:help` inside Claude Code reads your actual state — parked
slots, their true emails, running sessions, missing files — and names the specific
cause instead of making you match symptoms against a page.

> **Restart Claude Code after switching.** A running session holds the old
> credential. That's also why `claudeswitch use` refuses while a session is alive
> rather than letting it silently revert your switch.

**Platforms:** macOS and Linux/WSL are supported and tested (112 automated checks
across Debian, Ubuntu, Alpine and Fedora on every push). Windows-native is
best-effort and unverified — use WSL. [Details below](#platform-support).

**Requires** `python3` and `curl`. **Handles OAuth tokens** — see
[SECURITY.md](SECURITY.md) for exactly what is stored where.

---

## Quickstart

Four steps. Details for each are below.

```
1. install the plugin        /plugin install (or claude plugin install)
2. claudeswitch install-shim   makes the command work outside Claude Code
3. save, THEN /login, per account   one login per account, ever
4. claudeswitch use <name>     switch, then restart Claude Code
```

**Order matters in step 3:** `save` the account you're on *before* running
`/login`, because `/login` overwrites the live credential. Park first and nothing
is ever lost.

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
   pgrep -fl 'native-binary/claude|/claude$|Claude\.app|claude-desktop'  # expect no output
   ```
   Orphans can be cleared with `pkill -f 'native-binary/claude'`.
3. **Park it** — *you or Claude.* From a terminal:
   ```bash
   claudeswitch save work
   ```
   `save` prints which account it actually parked. Check that line matches what
   you intended before moving on.

**Park each account before logging in as the next one.** Step 3 has to happen
before you return to step 1 for the second account — `/login` overwrites the live
credential, so an unparked account is lost at that moment. If you do forget, the
next session warns you that the active account isn't parked.

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
option today. Reports from real Windows setups are welcome in
[issues](https://github.com/realwebthings/claudeswitch/issues).

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
idle. `save` has a stronger check that cannot be forced: it compares the stored
token against `~/.claude.json` and aborts if they disagree, because that mismatch
is what corrupts a slot.

---

## Not losing an account

Losing a token costs a `/login`, so two guards are on by default.

**`use` parks the outgoing account first.** Switching overwrites the live
credential, so if you were logged in as an account that isn't in a slot, its token
would be gone. Instead it lands in `_previous`:

```
$ claudeswitch use work
  parked outgoing account to '_previous' (recover with: claudeswitch use _previous)
active account = slot 'work'
```

Nothing is written when the outgoing account is already parked — the message says
so, and `_previous` keeps whatever it was holding.

**`save` won't silently clobber a different account.** Re-saving the same account
into its own slot is the normal refresh path and stays quiet, but pointing an
existing slot at a *different* account needs `CLAUDESWITCH_FORCE=1`.

**What still isn't protected: `/login` itself.** That's Claude Code's own command
and claudeswitch can't intercept it, so park *before* logging in:

```bash
claudeswitch save work     # park the current account FIRST
/login                     # now safe — this overwrites the live credential
claudeswitch save personal
```

As a net, the SessionStart hook notices when the active account is in no slot and
tells you to `save` it. To park such accounts automatically instead:

```bash
mkdir -p ~/.claude/claudeswitch && echo 1 > ~/.claude/claudeswitch/autopark
```

(If you set `CLAUDE_CONFIG_DIR`, put the flag under that directory instead —
`"$CLAUDE_CONFIG_DIR"/claudeswitch/autopark`. The warning message prints the exact
path for your setup.)

That's opt-in because it writes a token copy to disk without asking. Either way,
"already parked" is judged by **account**, not by token — Claude Code rotates
tokens on refresh, so a slot holding a stale token for the same account still
counts as parked.

---

## How it works

Logging in writes **two** pieces of state. Both must be swapped together.

### 1. OAuth tokens — one credential slot

Where the token lives depends on the platform.

**macOS** — one login Keychain entry:

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

**Linux, WSL, Windows/Git Bash** — one file, `~/.claude/.credentials.json`
(mode 600). Parked copies are sibling files in the directory claudeswitch owns:

```
~/.claude/.credentials.json               <- active; Claude Code reads only this
~/.claude-accounts/work.credentials.json      <- parked, survives /login
~/.claude-accounts/personal.credentials.json  <- parked, survives /login
```

Every write goes to a temp file in the same directory and is then `mv`'d into
place, so an interrupted switch can't leave a half-written credential that locks
you out of Claude Code. Tokens are written under `umask 077` and the parking
directory is `700` — a parked token is never more readable than the live one.

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
credential store or `~/.claude.json` — every config dir shares both. (On the
file backend the credential path *is* inside the config dir, and claudeswitch
honours `CLAUDE_CONFIG_DIR` accordingly — but `~/.claude.json`, which carries the
displayed identity, still sits outside it, so a switch is still needed.) It's useful
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

In every case a parked slot gets **the same protection Claude Code already gives
the live credential on that platform** — claudeswitch does not downgrade storage.
The real change is **N token copies instead of 1**: whatever can read the live
credential can now read every account you've parked.

- **macOS** — parked in your login Keychain, like the original. Nothing is
  written to disk in plaintext.
- **Linux / WSL / Windows** — Claude Code itself stores the token as a plaintext
  file (`~/.claude/.credentials.json`, mode 600); parked slots are the same
  format, mode 600, in a `700` directory. So the tokens are readable by your own
  user account and by root, exactly as the live one already is. If you back up
  your home directory, **your backups now contain N tokens** — exclude
  `~/.claude-accounts/` if that matters. Disk encryption is what protects these
  at rest.

If that's not acceptable, use `ANTHROPIC_API_KEY` per terminal instead. That
bypasses the credential store entirely, but usage is billed per token rather than
drawing on a Pro/Team seat, and a key in a settings file is plaintext on disk.

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

**Keychain permission prompts** (macOS)
macOS asking about the `security` command. Choose "Always Allow".

**`no credential file at ~/.claude/.credentials.json`** (Linux/WSL/Windows)
claudeswitch found no live credential to read. Open Claude Code and `/login`
first. If you *are* logged in and the file doesn't exist, your install keeps its
token somewhere else — on native Windows that's likely Credential Manager, which
isn't supported yet; run Claude Code under WSL instead. Please
[open an issue](https://github.com/realwebthings/claudeswitch/issues) with your
setup.

**Wrong backend detected**
Force it: `CLAUDESWITCH_BACKEND=file` or `CLAUDESWITCH_BACKEND=keychain`.

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

This depends on unofficial internals: the credential location (the Keychain
service name `Claude Code-credentials` on macOS, or `.credentials.json` inside the
config dir elsewhere), and the `oauthAccount` key in `~/.claude.json`. None is
public API. A Claude Code update could rename or relocate any of them, in which
case this breaks — the script checks what it finds and refuses to act on surprises
rather than half-applying a switch, but it cannot survive a rename.

Windows-native support is best-effort and unverified; WSL is the tested path for
Windows users.

The VSCode extension sidebar always uses `~/.claude` settings regardless of
account, since it ignores `CLAUDE_CONFIG_DIR`. Only the active credential
follows a switch there.

There is no true per-window account isolation: the active credential is global to
the machine. One account is active at a time.

---

## Testing

macOS is tested by using it. The Linux/WSL file backend is verified in
containers, because it can't run natively on a Mac and faking `uname` would only
exercise the branch, not the behaviour:

```bash
./test/run-docker.sh              # 4 distros + shellcheck
./test/run-docker.sh alpine       # one distro
./test/run-docker.sh shellcheck   # lint only
```

66 checks covering the save/use/rm lifecycle, that a switch moves both the token
and the displayed identity, that unrelated `~/.claude.json` keys survive, file
modes (600/700), atomic writes leaving no temp files, `CLAUDE_CONFIG_DIR`
handling, error paths and exit codes, corrupt/empty slots, `install-shim` profile
selection per shell, and the SessionStart hook.

Alpine is in the matrix on purpose — it uses BusyBox `find`/`stat`/`sed`, where
non-portable shell usage fails while passing on Debian. The repo is mounted
read-only, so tests can't touch your working tree.

---

## License

MIT
# claudeswitch
# claudeswitch
