---
description: Diagnose claudeswitch problems — switching not working, wrong email showing, command not found, refuses to switch, or a slot holding the wrong account. Use when the user is stuck switching Claude Code accounts or hits an error from the claudeswitch command.
argument-hint: "[describe the problem, or leave empty]"
---

Diagnose a `claudeswitch` problem. Problem described by user: `$ARGUMENTS`

**Gather state first, then match against the causes below.** Do not guess which
account is which or what went wrong — the checks are cheap and the failure modes
look alike from the outside.

## Step 1 — collect facts

Run these and read the output before saying anything:

```bash
claudeswitch list 2>&1
pgrep -fl 'native-binary/claude|/claude$|Claude\.app|claude-desktop|[Cc]laude\.exe' 2>/dev/null
command -v claudeswitch
ls ~/.claude-accounts/ 2>/dev/null
uname -s                                  # which credential backend applies
ls -l ~/.claude/.credentials.json 2>/dev/null   # non-macOS: the live credential
claudeswitch internal-unparked 2>&1       # non-empty = active account has no slot
ls ~/.claude/claudeswitch/autopark 2>/dev/null  # present = auto-park opted in
```

`list` reports each slot's real email via a live API lookup, plus the active
account. That is ground truth — a slot's *name* means nothing.

`uname -s` matters because storage differs: `Darwin` means the macOS Keychain
(`security`), anything else means a `.credentials.json` file. On Linux/WSL a
missing credential file is the most common cause of "no active credential" — the
user simply hasn't run `/login` in that config dir. `pgrep` is unavailable in Git
Bash on Windows; use `ps -W | grep -i claude` there.

`internal-unparked` prints the active account's email when it is in no slot, and
nothing otherwise. It is the quiet local check behind the SessionStart warning, so
it answers "is an account at risk right now?" without a full `list`. Empty output
also occurs offline or with an expired token, so treat empty as "no problem
detected", not proof.

If a `_previous` slot exists, `use` auto-parked an account that was about to be
overwritten. It is a real account worth renaming via `save <name>`, not junk.

## Step 2 — match the symptom

### "command not found: claudeswitch"

Only in a plain terminal, and expected before setup: a plugin's `bin/` is on PATH
only inside Claude Code sessions. Fix: run `claudeswitch install-shim` from
inside Claude Code, once. If it persists afterwards, the shim directory
(`~/.local/bin` by default) is not on their PATH — `install-shim` prints the
exact line to add.

### "refusing to switch — other Claude Code sessions are running"

Working as designed, not a bug. A live session rewrites the credential when its
token refreshes, which would silently revert the switch. The listed PIDs exclude
the session running the command, so anything shown is genuinely separate —
usually a forgotten VSCode sidebar chat.

Tell them to quit those sessions and retry. **Do not suggest
`CLAUDESWITCH_FORCE=1`** unless they insist and understand it can revert the
switch or corrupt a slot.

### Switched, but the old email still shows

Two distinct causes — check in this order:

1. **Session not restarted.** The credential is read at startup. Reload the
   VSCode window, or restart Claude Code.
2. **No parked identity for that slot.** If `ls ~/.claude-accounts/` has no
   `<name>.oauthAccount.json`, the token switches but the displayed email does
   not, because the email lives in `~/.claude.json`, not in the token. Fix: log
   in as that account and `claudeswitch save <name>` again.

`claudeswitch list` flags this directly — a slot missing its identity file shows
`[no identity file — run 'save <name>' again]`.

### "refusing to save — the active state is inconsistent"

The stored token and `~/.claude.json` name different accounts, because a
running session refreshed the token mid-operation. This check exists to stop a
slot being mislabeled.

Fix: quit Claude Code fully, `/login` as the account they actually want to park,
then retry. **Never work around this** — forcing it parks the wrong account's
token under a slot name, which needs another `/login` to repair.

### "the active account (...) is not parked in any slot"

A SessionStart notice, not an error. The live credential matches no slot, so a
future `/login` would destroy it. Fix: `claudeswitch save <name>`.

If they want this parked automatically in future:
`mkdir -p ~/.claude/claudeswitch && echo 1 > ~/.claude/claudeswitch/autopark`.
Mention that it writes a token copy to disk unprompted — it is opt-in for that
reason.

"Already parked" is judged by account (via the parked `oauthAccount.json`), not by
token, so a stale parked token for the same account counts as parked. If this
warning appears for an account that *is* parked, the slot is probably missing its
identity file — `list` shows `[no identity file]`; re-run `save <name>` to fix.

### "refusing to overwrite slot '<name>' — it holds a different account"

Working as designed. Re-saving the same account into its own slot is fine; this
only fires when the slot holds a *different* account, where overwriting would cost
that account a `/login`. Suggest a different slot name. Only mention
`CLAUDESWITCH_FORCE=1` if they explicitly want to repoint the slot.

### "parked outgoing account to '_previous'"

Informational. `use` parks the account being switched away from when it isn't in a
slot, so nothing is lost. Recover with `claudeswitch use _previous`, and give it a
real name via `claudeswitch save <name>` if they want to keep it.

### A slot holds the wrong account's token

`list` shows the real email per slot, so this is visible directly. Usually
caused by running `save` while a session was live.

Fix: quit Claude Code, `/login` as the correct account, re-run
`claudeswitch save <name>`. The token itself is not recoverable — a fresh login
is required.

### "(lookup failed — offline or token expired)"

`list` resolves emails through an API call. Either the machine is offline, or
that slot's refresh token has expired. Refresh tokens last roughly a month and
roll forward with use, so an account left idle can lapse. Fix: `/login` as it,
then `save` again.

### "no active credential found"

Nothing is logged in at all. Open Claude Code and run `/login`. The `claude` CLI
is not required — extension or desktop app is fine.

### Switch appears to work, then reverts

A session was running during the switch. Quit everything, verify with
`pgrep -fl 'native-binary/claude|Claude\.app'`, then switch again.

## Step 3 — report

State plainly: which account is active, what went wrong, and the one action they
should take next. Quote the actual error text rather than paraphrasing — the
messages are specific.

If the state looks healthy and the user is just unsure how to switch, show them:

```bash
claudeswitch list          # who's parked, who's active
claudeswitch use <name>    # switch, then restart Claude Code
```

## Things to never do

- Never claim which account a slot holds without checking `list`.
- Never suggest editing `~/.claude.json`, Keychain entries, or
  `.credentials.json` files by hand.
- Never recommend `CLAUDESWITCH_FORCE=1` as a first resort.
- Never say a switch succeeded without the user restarting — it has not taken
  effect in any running session.
