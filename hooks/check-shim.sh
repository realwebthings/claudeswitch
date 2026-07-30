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

# ---------------------------------------------------- unparked-account check ---
# If the active account matches no parked slot, a later /login destroys its token
# with no way back. Report that (or park it, if the user opted in).
#
# Default is report-only: writing a token copy to disk is the user's call, not a
# plugin's. Opt in with
#   echo 1 > "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/claudeswitch/autopark
# Runs before the shim notice below, which exits early for users who already have
# a shim installed.
#
# Any failure here is non-fatal: a SessionStart hook must never block a session.
autopark_check() {
  local cs auto out slot
  # Prefer the plugin's own bin: this hook runs before most users have installed
  # a shim, so relying on `command -v` would silently skip the check for exactly
  # the people who need it most.
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -x "$CLAUDE_PLUGIN_ROOT/bin/claudeswitch" ]; then
    cs="$CLAUDE_PLUGIN_ROOT/bin/claudeswitch"
  else
    cs="$(command -v claudeswitch 2>/dev/null)"
  fi
  [ -n "$cs" ] && [ -x "$cs" ] || return 0
  auto="$STATE_DIR/autopark"

  # A quiet local check: prints the active account's email only if it is in no
  # parked slot. Needs one API call to name the account, so it stays silent when
  # offline rather than delaying startup with a useless warning.
  out="$("$cs" internal-unparked 2>/dev/null)" || return 0
  [ -n "$out" ] || return 0          # empty = already parked, or unresolvable

  if [ -f "$auto" ]; then
    slot="$("$cs" internal-autopark 2>/dev/null)" || return 0
    [ -n "$slot" ] && echo "claudeswitch: parked the active account as '$slot' (auto-park is on)."
  else
    echo "claudeswitch: the active account ($out) is not parked in any slot."
    echo "  A future /login would overwrite it with no way back. Park it with:"
    echo "    claudeswitch save <name>"
    echo "  To park unrecognized accounts automatically from now on:"
    echo "    mkdir -p \"$STATE_DIR\" && echo 1 > \"$auto\""
  fi
}
autopark_check 2>/dev/null || true

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
