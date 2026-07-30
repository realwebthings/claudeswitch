---
description: List, switch, or park Claude Code accounts (multiple logins on one machine, macOS or Linux/WSL). Use when the user wants to change which Claude account is active, check which account they are on, add a second account, or asks why their email is wrong after switching.
argument-hint: "[list | use <name> | save <name> | rm <name>]"
---

Manage multiple Claude Code accounts via the `claudeswitch` command that ships
with this plugin (already on PATH).

User request: `$ARGUMENTS`

## What to run

| Intent | Command |
|---|---|
| "which account am I on?" / no arguments | `claudeswitch list` |
| "switch to X" | `claudeswitch use X` |
| "add / park this account as X" | `claudeswitch save X` |
| "remove slot X" | `claudeswitch rm X` |

If `$ARGUMENTS` is empty, run `claudeswitch list` and report the active account
plus what else is parked.

If the user names an account that has no slot yet, say so and explain the
one-time setup below — and check first whether the *currently active* account is
parked, because `/login` will overwrite it.

## Rules that matter

**A switch does not take effect in a running session.** After `use`, tell the
user to restart Claude Code. For the VSCode extension sidebar, they must reload
the window.

**`use` refuses while other Claude Code sessions are alive.** This is correct
behavior, not a bug: a live session rewrites the credential on token refresh and
would silently revert the switch. Do not reach for `CLAUDESWITCH_FORCE=1` to get
past it — tell the user to quit the other sessions. Only mention the override if
they explicitly insist and understand the risk.

**`save` refuses when the token and `~/.claude.json` name different accounts.**
This means a session refreshed the token mid-operation. The fix is: quit Claude
Code, `/login` as the intended account, retry. Never work around this check —
forcing it parks the wrong account's token under a slot name, which needs
another `/login` to repair.

**Never invent which account is which.** Slot names are arbitrary labels; the
email comes from a live API lookup. If `list` shows `(lookup failed)`, the
machine is offline or that slot's token expired — say that rather than guessing.

**`save` refuses to overwrite a slot holding a *different* account.** Re-saving
the same account into its own slot is the normal refresh and works silently. If
this fires, the user is about to cost that other account a `/login` — suggest a
different slot name rather than reaching for `CLAUDESWITCH_FORCE=1`.

**`use` auto-parks the account being switched away from** into `_previous`, if it
isn't already in a slot. So a switch never loses an account. If the user asks what
`_previous` is, it is a real account saved from being overwritten — suggest
`claudeswitch save <name>` to give it a proper name.

## Setting up a new account

One `/login` per account, ever. **Park before logging in** — `/login` overwrites
the live credential, so the account currently signed in is lost at that moment
unless it is already in a slot:

1. **Park the current account first**, if it isn't already: `claudeswitch save
   <name>`. Check with `claudeswitch list` — if the active account matches no
   slot, saving it now is what prevents a lost login.
2. Quit Claude Code fully, including the VSCode sidebar. Verify with
   `pgrep -fl 'native-binary/claude|/claude$|Claude\.app|claude-desktop'` — expect
   no output.
3. `/login` as the new account (via the CLI, or the extension's own account UI),
   then quit.
4. `claudeswitch save <name>` for the new account.
5. `claudeswitch list` to confirm both slots show the right emails.

If the user already ran `/login` without parking, the previous account's token is
gone and needs a fresh `/login` to recover. Say so plainly — nothing is corrupted,
but the shortcut for that account is lost until they log in as it again.

## Reporting back

Be concrete about which account is active and what the user must do next
(restart / reload). If a command failed, quote the actual error rather than
paraphrasing it — the messages are specific and actionable.
