#!/usr/bin/env bash
# claudeswitch installer
# Usage: curl -fsSL https://raw.githubusercontent.com/realwebthings/claudeswitch/main/install.sh | bash
# Or with a specific version:
#   curl -fsSL https://raw.githubusercontent.com/realwebthings/claudeswitch/main/install.sh | bash -s -- --version v1.8.0

set -euo pipefail

REPO="realwebthings/claudeswitch"
INSTALL_DIR="${CLAUDESWITCH_INSTALL_DIR:-$HOME/.local/bin}"
VERSION="${1:-}"
# strip leading --version flag if passed via bash -s --
case "${VERSION:-}" in --version) VERSION="${2:-}" ;; esac

die() { echo "install: $*" >&2; exit 1; }

print_banner() {
  local v="${VERSION:-latest}"
  echo ""
  echo "  ╔═══════════════════════════════════════════════════════════════╗"
  echo "  ║              CLAUDESWITCH  ${v}                               ║"
  echo "  ║       Multiple Claude accounts, one machine. Zero re-logins.      ║"
  echo "  ╚═══════════════════════════════════════════════════════════════╝"
  echo ""
  echo "  COMMANDS"
  echo "    claudeswitch save <name>   park the current logged-in account"
  echo "    claudeswitch use  <name>   switch to a parked account"
  echo "    claudeswitch list          show all slots + active account"
  echo "    claudeswitch whoami        show the active account only"
  echo "    claudeswitch rm   <name>   delete a parked slot"
  echo "    claudeswitch update        update to latest version"
  echo "    claudeswitch help          show full help"
  echo ""
  echo "  ── QUICK START (do this once per account) ──────────────────────"
  echo ""
  echo "  Step 1 — Set up your FIRST account"
  echo "    a. Log in to Claude Code (terminal: claude, or VSCode extension)"
  echo "    b. Run:  claudeswitch save work"
  echo "       This parks the current account under the name 'work'."
  echo ""
  echo "  Step 2 — Set up your SECOND account"
  echo "    a. Switch accounts:"
  echo "         Terminal:  type /login inside the claude session"
  echo "         VSCode:    click your account avatar → Switch Account"
  echo "    b. Run:  claudeswitch save personal"
  echo "       This parks the second account under the name 'personal'."
  echo ""
  echo "  Step 3 — Verify both accounts are saved"
  echo "    Run:  claudeswitch list"
  echo "    You should see both 'work' and 'personal' with their emails."
  echo ""
  echo "  Step 4 — Switch any time"
  echo "    Run:  claudeswitch use work"
  echo "    Then restart Claude Code (or reload the VSCode window)."
  echo "    That's it — no browser, no /login, ever again."
  echo ""
  echo "  ────────────────────────────────────────────────────────────────"
  echo "  Docs: https://github.com/realwebthings/claudeswitch"
  echo ""
}

# Resolve version — try releases API first, fall back to main branch
if [ -z "$VERSION" ]; then
  VERSION="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
    | grep '"tag_name"' | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1 || true)"
fi

echo "Installing claudeswitch ${VERSION:-latest} to $INSTALL_DIR ..."

mkdir -p "$INSTALL_DIR"

# Download: use release tag if we have one, otherwise main branch
if [ -n "$VERSION" ]; then
  URL="https://raw.githubusercontent.com/$REPO/$VERSION/bin/claudeswitch"
else
  URL="https://raw.githubusercontent.com/$REPO/main/bin/claudeswitch"
fi

curl -fsSL "$URL" -o "$INSTALL_DIR/claudeswitch" \
  || die "download failed from $URL"
chmod +x "$INSTALL_DIR/claudeswitch"

echo "Installed: $INSTALL_DIR/claudeswitch"

# PATH check
case ":$PATH:" in
  *":$INSTALL_DIR:"*)
    print_banner
    ;;
  *)
    tilde_dir="\$HOME${INSTALL_DIR#"$HOME"}"
    path_line="export PATH=\"$tilde_dir:\$PATH\""
    case "${SHELL:-}" in
      */zsh)  profile="$HOME/.zshrc" ;;
      */bash)
        [ "$(uname -s 2>/dev/null)" = "Darwin" ] && profile="$HOME/.bash_profile" || profile="$HOME/.bashrc" ;;
      */fish) profile="" ;;
      *)      profile="$HOME/.profile" ;;
    esac
    echo
    echo "$INSTALL_DIR is not on your PATH."
    if [ -t 0 ]; then
      printf "Add it to %s now? [y/N] " "$profile"
      read -r reply
      case "$reply" in
        [yY]*)
          { echo ""; echo "# added by claudeswitch installer"; echo "$path_line"; } >> "$profile"
          echo "Added. Run: source $profile"
          ;;
        *)
          echo "Add this to your shell profile manually:"
          echo "  $path_line"
          ;;
      esac
    else
      echo "Add this to $profile:"
      echo "  $path_line"
    fi
    print_banner
    ;;
esac
