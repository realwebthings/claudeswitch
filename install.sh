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

# Resolve version — try releases API first, fall back to main branch
if [ -z "$VERSION" ]; then
  if command -v python3 >/dev/null 2>&1; then
    VERSION="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
      | python3 -c 'import sys,json;print(json.load(sys.stdin)["tag_name"])' 2>/dev/null || true)"
  fi
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
    echo "Done. Run: claudeswitch list"
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
    ;;
esac
