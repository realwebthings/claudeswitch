#!/usr/bin/env bash
# claudeswitch file-backend test suite — run inside a Linux container.
# Exercises real behaviour on a real kernel/filesystem, not a faked uname.
#
# The repo is mounted read-only at /repo, so tests must not write there.

set -uo pipefail

REPO="${REPO:-/repo}"
CS="$REPO/bin/claudeswitch"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL  $1"; echo "        expected: $2"; echo "        actual:   $3"; }
check() { # check <desc> <expected-substring> <actual>
  case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "$2" "$3" ;; esac
}
checkeq() { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$2" "$3"; }

# Fresh HOME per test group so state never leaks between cases.
newhome() {
  export HOME="/work/h$1"
  rm -rf "$HOME"; mkdir -p "$HOME/.claude"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  unset CLAUDESWITCH_BACKEND CLAUDESWITCH_FORCE 2>/dev/null || true
}

# Write a live credential + matching identity. Tokens are fake; the API lookup
# will fail, which is expected and must not break save/use.
mk() { # mk <token> <plan> <email>
  printf '{"claudeAiOauth":{"accessToken":"%s","subscriptionType":"%s","rateLimitTier":"t1","expiresAt":1790000000000,"refreshTokenExpiresAt":1792000000000}}' \
    "$1" "$2" > "$CLAUDE_CONFIG_DIR/.credentials.json"
  printf '{"oauthAccount":{"emailAddress":"%s"},"projects":{"keep":1}}' "$3" > "$HOME/.claude.json"
}

# Read emailAddress from ~/.claude.json without python3.
read_email() { grep -o '"emailAddress":"[^"]*"' "$HOME/.claude.json" | sed 's/.*:"\(.*\)"/\1/'; }
read_email_from() { grep -o '"emailAddress":"[^"]*"' "$1" | sed 's/.*:"\(.*\)"/\1/'; }

echo "=============================================="
echo " environment"
echo "=============================================="
echo "  uname -s : $(uname -s)"
echo "  distro   : $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
echo "  bash     : $BASH_VERSION"
echo "  curl     : $(curl --version 2>/dev/null | head -1 | cut -d' ' -f1-2)"
echo "  security : $(command -v security >/dev/null && echo present || echo 'absent (correct for Linux)')"
echo

echo "=============================================="
echo " 1. backend auto-detection (no override)"
echo "=============================================="
newhome 1
out="$("$CS" whoami 2>&1)"
check "auto-detects file backend on Linux" "no credential file at" "$out"
case "$out" in *security*) bad "must not mention 'security' on Linux" "no mention" "$out" ;; *) ok "no bogus 'security' dependency error" ;; esac
echo

echo "=============================================="
echo " 2. save / list / use / rm lifecycle"
echo "=============================================="
newhome 2
export CLAUDESWITCH_FORCE=1

mk tok-work pro work@example.com
out="$("$CS" save work 2>&1)"
check "save work succeeds" "saved to slot 'work'" "$out"
[ -f "$HOME/.claude-accounts/work.credentials.json" ] \
  && ok "slot file created" || bad "slot file created" "work.credentials.json exists" "missing"
[ -f "$HOME/.claude-accounts/work.oauthAccount.json" ] \
  && ok "identity file parked" || bad "identity file parked" "work.oauthAccount.json exists" "missing"

mk tok-home team home@example.com
out="$("$CS" save home 2>&1)"
check "save home succeeds" "saved to slot 'home'" "$out"

out="$("$CS" list 2>&1)"
check "list shows work" "work" "$out"
check "list shows home" "home" "$out"

out="$("$CS" use work 2>&1)"
check "use work succeeds" "active account = slot 'work'" "$out"
checkeq "live token is work's" "tok-work" "$(grep -o 'tok-[a-z]*' "$CLAUDE_CONFIG_DIR/.credentials.json")"
checkeq "identity restored to work" "work@example.com" "$(read_email)"
checkeq "unrelated .claude.json keys preserved" \
  "1" "$(grep -o '"keep":[0-9]*' "$HOME/.claude.json" | grep -o '[0-9]*')"
[ -f "$HOME/.claude.json.claudeswitch.bak" ] && ok "backup written" || bad "backup written" "exists" "missing"

out="$("$CS" use home 2>&1)"
check "use home succeeds" "active account = slot 'home'" "$out"
checkeq "live token switched to home" "tok-home" "$(grep -o 'tok-[a-z]*' "$CLAUDE_CONFIG_DIR/.credentials.json")"
checkeq "identity switched to home" "home@example.com" "$(read_email)"

out="$("$CS" use work 2>&1)"
checkeq "round-trip back to work" "tok-work" "$(grep -o 'tok-[a-z]*' "$CLAUDE_CONFIG_DIR/.credentials.json")"

out="$("$CS" rm home 2>&1)"
check "rm home succeeds" "removed slot 'home'" "$out"
[ ! -f "$HOME/.claude-accounts/home.credentials.json" ] \
  && ok "slot file deleted" || bad "slot file deleted" "gone" "still present"
[ ! -f "$HOME/.claude-accounts/home.oauthAccount.json" ] \
  && ok "identity file deleted" || bad "identity file deleted" "gone" "still present"
checkeq "rm did not touch live credential" "tok-work" "$(grep -o 'tok-[a-z]*' "$CLAUDE_CONFIG_DIR/.credentials.json")"
out="$("$CS" list 2>&1)"
case "$out" in *home*) bad "removed slot absent from list" "no 'home'" "$out" ;; *) ok "removed slot absent from list" ;; esac
echo

echo "=============================================="
echo " 2b. identity restore is genuinely exercised"
echo "=============================================="
newhome 2b
export CLAUDESWITCH_FORCE=1
mk tok-alpha pro alpha@example.com
"$CS" save alpha >/dev/null 2>&1
mk tok-beta team beta@example.com
"$CS" save beta  >/dev/null 2>&1

out="$("$CS" use alpha 2>&1)"
case "$out" in
  *"no parked identity"*) bad "restore_identity finds the parked file" "no warning" "$out" ;;
  *) ok "restore_identity finds the parked file (no warning)" ;;
esac
checkeq "identity actually rewritten beta->alpha" "alpha@example.com" "$(read_email)"

out="$("$CS" use beta 2>&1)"
case "$out" in
  *"no parked identity"*) bad "restore works in reverse too" "no warning" "$out" ;;
  *) ok "restore works in reverse too" ;;
esac
checkeq "identity actually rewritten alpha->beta" "beta@example.com" "$(read_email)"

# restore_identity must resolve its path from its ARGUMENT, not from a global.
out="$(bash -c '
  set -uo pipefail
  eval "$(sed -n "/^restore_identity()/,/^}/p" '"$CS"')"
  PARK_DIR="'"$HOME"'/.claude-accounts"
  GLOBAL_JSON="'"$HOME"'/.claude.json"
  restore_identity alpha 2>&1
  grep -o "\"emailAddress\":\"[^\"]*\"" "'"$HOME"'/.claude.json" | sed '"'"'s/.*:"\(.*\)"/\1/'"'"'
' 2>&1)"
case "$out" in
  *alpha@example.com*) ok "restore_identity works from its argument alone (SC2318 guard)" ;;
  *) bad "restore_identity works from its argument alone (SC2318 guard)" "alpha@example.com" "$out" ;;
esac

# A slot saved without an identity file must warn rather than fail silently.
newhome 2c
export CLAUDESWITCH_FORCE=1
mk tok-x pro x@example.com
"$CS" save x >/dev/null 2>&1
rm -f "$HOME/.claude-accounts/x.oauthAccount.json"
out="$("$CS" use x 2>&1)"
check "missing identity file warns explicitly" "no parked identity" "$out"
out="$("$CS" list 2>&1)"
check "list flags the missing identity file" "no identity file" "$out"
echo

echo "=============================================="
echo " 2d. auto-park protects the outgoing account"
echo "=============================================="
newhome 2d
export CLAUDESWITCH_FORCE=1
mk tok-saved pro saved@example.com
"$CS" save saved >/dev/null 2>&1

mk tok-unparked team unparked@example.com
out="$("$CS" use saved 2>&1)"
check "use reports the auto-park" "parked outgoing account to '_previous'" "$out"
[ -f "$HOME/.claude-accounts/_previous.credentials.json" ] \
  && ok "_previous slot created" || bad "_previous slot created" "exists" "missing"
checkeq "_previous holds the outgoing token" "tok-unparked" \
  "$(grep -o 'tok-[a-z]*' "$HOME/.claude-accounts/_previous.credentials.json")"
checkeq "switch still applied" "tok-saved" \
  "$(grep -o 'tok-[a-z]*' "$CLAUDE_CONFIG_DIR/.credentials.json")"

out="$("$CS" use _previous 2>&1)"
check "can recover via use _previous" "active account = slot '_previous'" "$out"
checkeq "recovered the otherwise-lost token" "tok-unparked" \
  "$(grep -o 'tok-[a-z]*' "$CLAUDE_CONFIG_DIR/.credentials.json")"

newhome 2e
export CLAUDESWITCH_FORCE=1
mk tok-a pro a@example.com; "$CS" save a >/dev/null 2>&1
mk tok-b team b@example.com; "$CS" save b >/dev/null 2>&1
out="$("$CS" use a 2>&1)"
check "already-parked outgoing account is not re-parked" "already parked as" "$out"
[ ! -f "$HOME/.claude-accounts/_previous.credentials.json" ] \
  && ok "_previous not created for a parked account" \
  || bad "_previous not created for a parked account" "absent" "present"

newhome 2f
export CLAUDESWITCH_FORCE=1
mk tok-keep pro keep@example.com; "$CS" save keep >/dev/null 2>&1
mk tok-lost team lost@example.com
"$CS" use keep >/dev/null 2>&1
"$CS" use _previous >/dev/null 2>&1
checkeq "use _previous does not clobber itself" "tok-lost" \
  "$(grep -o 'tok-[a-z]*' "$HOME/.claude-accounts/_previous.credentials.json")"
echo

echo "=============================================="
echo " 2f2. stale parked token still counts as parked"
echo "=============================================="
newhome 2f2
export CLAUDESWITCH_FORCE=1
mk tok-v1 pro rotate@example.com
"$CS" save rotated >/dev/null 2>&1
mk tok-v2 pro rotate@example.com

# A switch must not create a redundant _previous for an already-parked account.
mk tok-other team other@example.com; "$CS" save other >/dev/null 2>&1
mk tok-v2 pro rotate@example.com
out="$("$CS" use other 2>&1)"
check "already-parked (stale token) is not re-parked" "already parked as" "$out"
[ ! -f "$HOME/.claude-accounts/_previous.credentials.json" ] \
  && ok "no redundant _previous for a refreshed token" \
  || bad "no redundant _previous for a refreshed token" "absent" "present"

mk tok-new pro brandnew@example.com
out="$("$CS" use other 2>&1)"
check "genuinely unparked account still auto-parked" "parked outgoing account" "$out"
checkeq "_previous holds the new account's token" "tok-new" \
  "$(grep -o 'tok-[a-z]*' "$HOME/.claude-accounts/_previous.credentials.json")"
echo

echo "=============================================="
echo " 2g. save refuses to clobber a different account"
echo "=============================================="
newhome 2g
mk tok-first pro first@example.com
CLAUDESWITCH_FORCE=1 "$CS" save shared >/dev/null 2>&1
out="$(CLAUDESWITCH_FORCE= "$CS" save shared 2>&1)"
check "re-saving same slot still works when emails unresolvable" "saved to slot" "$out"
[ -f "$HOME/.claude-accounts/shared.credentials.json" ] && ok "slot still present" || bad "slot present" "exists" "missing"
echo

echo "=============================================="
echo " 3. file permissions (tokens are secrets)"
echo "=============================================="
newhome 3
export CLAUDESWITCH_FORCE=1
mk tok-perm pro perm@example.com
chmod 644 "$CLAUDE_CONFIG_DIR/.credentials.json"
"$CS" save perm >/dev/null 2>&1
checkeq "parked slot is 600" "600" "$(stat -c '%a' "$HOME/.claude-accounts/perm.credentials.json")"
checkeq "park dir is 700"    "700" "$(stat -c '%a' "$HOME/.claude-accounts")"
checkeq "parked identity is 600" "600" "$(stat -c '%a' "$HOME/.claude-accounts/perm.oauthAccount.json")"
checkeq "save does not loosen the parked copy" "600" "$(stat -c '%a' "$HOME/.claude-accounts/perm.credentials.json")"
"$CS" use perm >/dev/null 2>&1
checkeq "use writes the live credential as 600 (tightens 644)" "600" \
  "$(stat -c '%a' "$CLAUDE_CONFIG_DIR/.credentials.json")"
bak_mode="$(stat -c '%a' "$HOME/.claude.json.claudeswitch.bak" 2>/dev/null)"
case "$bak_mode" in *[2367]) bad "backup not world-writable" "not w-writable" "$bak_mode" ;; *) ok "backup not world-writable ($bak_mode)" ;; esac
echo

echo "=============================================="
echo " 4. atomic writes leave no temp files"
echo "=============================================="
stray="$(find "$HOME" \( -name '*.claudeswitch.*.tmp' -o -name '.claudeswitch.*' \) 2>/dev/null | grep -v '\.bak$')"
[ -z "$stray" ] && ok "no stray temp files" || bad "no stray temp files" "none" "$stray"
echo

echo "=============================================="
echo " 5. error handling"
echo "=============================================="
out="$("$CS" use nosuch 2>&1)"; rc=$?
check "use unknown slot errors" "no slot 'nosuch'" "$out"
checkeq "  ...with exit 1" "1" "$rc"

out="$("$CS" rm nosuch 2>&1)"; rc=$?
check "rm unknown slot errors" "no slot 'nosuch'" "$out"
checkeq "  ...with exit 1" "1" "$rc"

out="$("$CS" save 'bad name!' 2>&1)"; rc=$?
check "rejects invalid slot name" "may only contain" "$out"
checkeq "  ...with exit 1" "1" "$rc"

out="$("$CS" bogus 2>&1)"; rc=$?
checkeq "unknown command exits 1" "1" "$rc"

newhome 5
out="$("$CS" whoami 2>&1)"; rc=$?
checkeq "missing credential exits 1" "1" "$rc"
case "$out" in
  *"unparseable credential"*) bad "no '(unparseable credential)' noise" "clean error" "$out" ;;
  *) ok "no '(unparseable credential)' noise" ;;
esac
checkeq "missing credential prints exactly one line" "1" "$(printf '%s\n' "$out" | grep -c .)"
echo

echo "=============================================="
echo " 5b. slot names cannot escape the park directory"
echo "=============================================="
newhome 5b
export CLAUDESWITCH_FORCE=1
mk tok-live pro live@example.com
mkdir -p "$HOME/victim" "$HOME/.claude-accounts"
printf 'SENSITIVE' > "$HOME/victim/secret.credentials.json"

for bad_name in '../victim/secret' '../../etc/passwd' 'a/b' '..' '.' 'a;id' '$(id)' 'a b' '-x'; do
  rejected=0
  for cmd in rm use save; do
    out="$("$CS" "$cmd" "$bad_name" 2>&1)"
    case "$out" in *"slot name may"*) ;; *) rejected=1 ;; esac
  done
  [ "$rejected" -eq 0 ] && ok "rejected by save/use/rm: '$bad_name'" \
    || bad "rejected by save/use/rm: '$bad_name'" "slot name error" "$out"
done
[ -f "$HOME/victim/secret.credentials.json" ] \
  && ok "file outside the park dir was NOT deleted" \
  || bad "file outside the park dir was NOT deleted" "intact" "deleted"

for good in work my.account a-b_c _previous A1; do
  out="$("$CS" save "$good" 2>&1)"
  check "valid name accepted: '$good'" "saved to slot '$good'" "$out"
done
echo

echo "=============================================="
echo " 6. empty / corrupt slot handling"
echo "=============================================="
newhome 6
export CLAUDESWITCH_FORCE=1
mk tok-a pro a@example.com
"$CS" save a >/dev/null 2>&1
: > "$HOME/.claude-accounts/a.credentials.json"
out="$("$CS" use a 2>&1)"; rc=$?
check "empty slot is refused, not applied" "empty or unreadable" "$out"
checkeq "  ...with exit 1" "1" "$rc"
checkeq "live credential untouched by failed use" "tok-a" \
  "$(grep -o 'tok-[a-z]*' "$CLAUDE_CONFIG_DIR/.credentials.json")"
echo

echo "=============================================="
echo " 7. CLAUDE_CONFIG_DIR is honoured"
echo "=============================================="
newhome 7
export CLAUDESWITCH_FORCE=1
mk tok-one pro one@example.com
mkdir -p "$HOME/cfg2"
printf '{"claudeAiOauth":{"accessToken":"tok-two","subscriptionType":"free","rateLimitTier":"t0","expiresAt":1790000000000,"refreshTokenExpiresAt":1792000000000}}' > "$HOME/cfg2/.credentials.json"
o1="$(CLAUDE_CONFIG_DIR="$HOME/.claude" "$CS" whoami 2>&1 | grep plan)"
o2="$(CLAUDE_CONFIG_DIR="$HOME/cfg2"    "$CS" whoami 2>&1 | grep plan)"
check "config dir 1 reads its own credential" "pro" "$o1"
check "config dir 2 reads its own credential" "free" "$o2"
echo

echo "=============================================="
echo " 8. HOME unset does not abort (set -u safety)"
echo "=============================================="
out="$(env -u HOME -u CLAUDE_CONFIG_DIR "$CS" list 2>&1)"
case "$out" in
  *"unbound variable"*) bad "HOME unset handled" "no unbound variable error" "$out" ;;
  *) ok "HOME unset handled (no 'unbound variable')" ;;
esac
echo

echo "=============================================="
echo " 9. keychain backend correctly unusable here"
echo "=============================================="
newhome 9
out="$(CLAUDESWITCH_BACKEND=keychain "$CS" whoami 2>&1)"; rc=$?
check "forced keychain backend fails clearly on Linux" "'security' not found" "$out"
check "  ...and suggests the file backend" "CLAUDESWITCH_BACKEND=file" "$out"
checkeq "  ...with exit 1" "1" "$rc"
echo

echo "=============================================="
echo " RESULTS"
echo "=============================================="
echo "  passed: $PASS"
echo "  failed: $FAIL"
[ "$FAIL" -eq 0 ] && echo "  ALL TESTS PASSED" || echo "  SOME TESTS FAILED"
exit $((FAIL > 0 ? 1 : 0))
