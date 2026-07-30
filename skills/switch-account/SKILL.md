---
description: List, switch, or park Claude Code accounts (multiple logins on one Mac). Use when the user wants to change which Claude account is active, check which account they are on, add a second account, or asks why their email is wrong after switching.
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
one-time setup: quit Claude Code, `/login` as that account, then
`claudeswitch save <name>`.

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

## Setting up a new account

One `/login` per account, ever:

1. Quit Claude Code fully, including the VSCode sidebar. Verify with
   `pgrep -fl 'native-binary/claude'` — expect no output.
2. `claude`, then `/login` as the account, then quit.
3. `claudeswitch save <name>`
4. `claudeswitch list` to confirm the slot shows the right email.

## Reporting back

Be concrete about which account is active and what the user must do next
(restart / reload). If a command failed, quote the actual error rather than
paraphrasing it — the messages are specific and actionable.
