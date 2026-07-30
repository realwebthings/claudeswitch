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
CACHE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/claudeswitch/claudeswitch"

# Stale-version notice — separate from the shim notice, and not nag-limited,
# because a leftover old version keeps mattering until it is cleaned up.
#
# `claude plugin update` leaves the previous version directory in place. That is
# harmless (the shim sorts by version and picks the newest) but it means the
# in-session PATH can still point at the old copy until the window is reloaded.
# Only report it — a plugin must not update or delete itself: that would let a
# repo push code onto machines without the user opting in.
if [ -d "$CACHE_ROOT" ]; then
  versions="$(ls -1 "$CACHE_ROOT" 2>/dev/null | sort -V)"
  count="$(printf '%s\n' "$versions" | grep -c . || true)"
  if [ "${count:-0}" -gt 1 ]; then
    newest="$(printf '%s\n' "$versions" | tail -1)"
    running="$(command -v claudeswitch 2>/dev/null || true)"
    case "$running" in
      *"/$newest/"*) : ;;   # already on the newest — nothing to say
      */plugins/cache/*)
        echo "claudeswitch: this session is running an older version. Reload the window to pick up $newest."
        ;;
    esac
  fi
fi

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
