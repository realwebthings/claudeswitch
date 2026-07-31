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

# Resolve version
if [ -z "$VERSION" ]; then
  VERSION="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["tag_name"])' 2>/dev/null)" \
    || die "could not fetch latest release — check your internet connection"
fi

echo "Installing claudeswitch $VERSION to $INSTALL_DIR ..."

mkdir -p "$INSTALL_DIR"

# Download the script directly from the release tag
curl -fsSL "https://raw.githubusercontent.com/$REPO/$VERSION/bin/claudeswitch" \
  -o "$INSTALL_DIR/claudeswitch"
chmod +x "$INSTALL_DIR/claudeswitch"

echo "Installed: $INSTALL_DIR/claudeswitch"

# PATH check
case ":$PATH:" in
  *":$INSTALL_DIR:"*)
    echo "Done. Run: claudeswitch list"
    ;;
  *)
    tilde_dir="\$HOME${INSTALL_DIR#"$HOME"}"
    path_line="export PATH=\"$tilde_dir:\$PATH\""
    case "${SHELL:-}" in
      */zsh)  profile="$HOME/.zshrc" ;;
      */bash)
        [ "$(uname -s)" = "Darwin" ] && profile="$HOME/.bash_profile" || profile="$HOME/.bashrc" ;;
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
    ;;
esac
