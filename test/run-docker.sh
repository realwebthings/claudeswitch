#!/usr/bin/env bash
# Run the file-backend test suite on real Linux, across several distros.
#
# The file backend cannot be meaningfully tested on macOS (which uses the
# Keychain backend), and faking `uname` only exercises the branch, not the
# behaviour — BusyBox vs GNU `find`/`stat`/`sed` differences show up only on a
# real distro. So the Linux path is verified in containers.
#
#   ./test/run-docker.sh              # all distros + shellcheck
#   ./test/run-docker.sh debian       # one distro
#   ./test/run-docker.sh shellcheck   # lint only
#
# The repo is mounted read-only, so a test can never modify the working tree.

set -uo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"
SUITE="$REPO/test/file-backend-test.sh"

# Alpine is included deliberately: it uses BusyBox coreutils, which is where
# non-portable `find`/`stat`/`sed` usage breaks. Ubuntu is what most WSL users
# actually run.
run_distro() {
  local image="$1" install="$2"
  printf '%-18s ' "$image"
  local out
  out="$(docker run --rm \
    -v "$REPO:/repo:ro" \
    -v "$SUITE:/test.sh:ro" \
    "$image" sh -c "$install; mkdir -p /work; bash /test.sh" 2>&1)"
  local totals
  totals="$(printf '%s\n' "$out" | grep -E 'passed:|failed:' | tr -d '\n' | tr -s ' ')"
  if printf '%s\n' "$out" | grep -q 'ALL TESTS PASSED'; then
    echo "OK  $totals"
  else
    echo "FAILED $totals"
    printf '%s\n' "$out" | grep -B1 -A3 'FAIL'
    return 1
  fi
}

APT='apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq python3 curl procps zsh >/dev/null 2>&1'
APK='apk add --no-cache bash python3 curl procps >/dev/null 2>&1'
DNF='dnf install -y -q python3 curl procps-ng zsh >/dev/null 2>&1'

rc=0
case "${1:-all}" in
  debian) run_distro debian:12-slim "$APT" || rc=1 ;;
  ubuntu) run_distro ubuntu:24.04   "$APT" || rc=1 ;;
  alpine) run_distro alpine:3.20    "$APK" || rc=1 ;;
  fedora) run_distro fedora:41      "$DNF" || rc=1 ;;
  shellcheck) ;;
  all)
    run_distro debian:12-slim "$APT" || rc=1
    run_distro ubuntu:24.04   "$APT" || rc=1
    run_distro alpine:3.20    "$APK" || rc=1
    run_distro fedora:41      "$DNF" || rc=1
    ;;
  *) echo "usage: $0 [all|debian|ubuntu|alpine|fedora|shellcheck]" >&2; exit 2 ;;
esac

if [ "${1:-all}" = "all" ] || [ "${1:-all}" = "shellcheck" ]; then
  printf '%-18s ' shellcheck
  if docker run --rm -v "$REPO:/repo:ro" koalaman/shellcheck:stable \
       --severity=warning --shell=bash /repo/bin/claudeswitch /repo/hooks/check-shim.sh 2>&1 \
       | grep -q .; then
    echo "WARNINGS"
    docker run --rm -v "$REPO:/repo:ro" koalaman/shellcheck:stable \
      --severity=warning --shell=bash /repo/bin/claudeswitch /repo/hooks/check-shim.sh
    rc=1
  else
    echo "OK  no warnings"
  fi
fi

exit $rc
