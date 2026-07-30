#!/bin/bash
# SessionStart hook — remind the user to install the shim, once.
#
# A plugin's bin/ is only on PATH inside Claude Code sessions, but
# `claudeswitch use` requires Claude Code to be QUIT. Without a shim on the
# user's own PATH, the command is unavailable exactly when it is needed.
#
# This only *detects* and *reports*. It deliberately does not write to
# ~/.local/bin: that is outside plugin-managed space, and silently adding an
# executable to a user's PATH is not something a plugin should do unasked.
#
# Stays quiet when the shim already exists, or once the user has been told and
# chosen not to install it.

set -uo pipefail

STATE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/claudeswitch"
NOTIFIED="$STATE_DIR/shim-notice-shown"

# Already installed anywhere on PATH? Nothing to say.
if command -v claudeswitch >/dev/null 2>&1; then
  # A plugin-cache path means we are seeing the plugin's own bin/, not a shim,
  # so the terminal case is still unsolved. Any other path is a real shim.
  resolved="$(command -v claudeswitch)"
  case "$resolved" in
    */plugins/cache/*) : ;;   # plugin bin only — fall through to the notice
    *) exit 0 ;;              # a shim (or manual install) exists — done
  esac
fi

# Only nag once. The user may have read the notice and declined.
[ -f "$NOTIFIED" ] && exit 0

mkdir -p "$STATE_DIR" 2>/dev/null || true
: > "$NOTIFIED" 2>/dev/null || true

cat <<'MSG'
claudeswitch: run `claudeswitch install-shim` once so the command also works
in a plain terminal. Switching accounts requires Claude Code to be quit, and a
plugin's bin/ is only on PATH inside Claude Code sessions.
MSG
