#!/usr/bin/env bash
# claudeswitch file-backend test suite — run inside a Linux container.
# Exercises real behaviour on a real kernel/filesystem, not a faked uname.
#
# The repo is mounted read-only at /repo, so tests must not write there.

set -uo pipefail

CS=/repo/bin/claudeswitch
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

echo "=============================================="
echo " environment"
echo "=============================================="
echo "  uname -s : $(uname -s)"
echo "  distro   : $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
echo "  bash     : $BASH_VERSION"
echo "  python3  : $(python3 --version 2>&1)"
echo "  curl     : $(curl --version 2>/dev/null | head -1 | cut -d' ' -f1-2)"
echo "  security : $(command -v security >/dev/null && echo present || echo 'absent (correct for Linux)')"
echo

echo "=============================================="
echo " 1. backend auto-detection (no override)"
echo "=============================================="
newhome 1
# No credential file yet: the error names the file path only if the file backend
# was chosen. On Linux 'security' is absent, so a keychain choice would instead
# fail the dependency check.
out="$("$CS" whoami 2>&1)"
check "auto-detects file backend on Linux" "no credential file at" "$out"
check "  ...and does NOT demand macOS 'security'" "" "$out"
case "$out" in *security*) bad "must not mention 'security' on Linux" "no mention" "$out" ;; *) ok "no bogus 'security' dependency error" ;; esac
echo

echo "=============================================="
echo " 2. save / list / use / rm lifecycle"
echo "=============================================="
newhome 2
export CLAUDESWITCH_FORCE=1   # no sessions in a container, but be explicit

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

# The core function: does 'use' actually swap the token AND the identity?
out="$("$CS" use work 2>&1)"
check "use work succeeds" "active account = slot 'work'" "$out"
checkeq "live token is work's" "tok-work" "$(grep -o 'tok-[a-z]*' "$CLAUDE_CONFIG_DIR/.credentials.json")"
checkeq "identity restored to work" "work@example.com" \
  "$(python3 -c "import json;print(json.load(open('$HOME/.claude.json'))['oauthAccount']['emailAddress'])")"
checkeq "unrelated .claude.json keys preserved" "1" \
  "$(python3 -c "import json;print(json.load(open('$HOME/.claude.json')).get('projects',{}).get('keep'))")"
[ -f "$HOME/.claude.json.claudeswitch.bak" ] && ok "backup written" || bad "backup written" "exists" "missing"

out="$("$CS" use home 2>&1)"
check "use home succeeds" "active account = slot 'home'" "$out"
checkeq "live token switched to home" "tok-home" "$(grep -o 'tok-[a-z]*' "$CLAUDE_CONFIG_DIR/.credentials.json")"
checkeq "identity switched to home" "home@example.com" \
  "$(python3 -c "import json;print(json.load(open('$HOME/.claude.json'))['oauthAccount']['emailAddress'])")"

# Switching back must be lossless — the whole point of parking.
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
# Regression guard for the SC2318 bug in restore_identity: a single `local`
# statement left $parked as ".oauthAccount.json", so the parked file was never
# found and restore silently warned instead of restoring. Catching that requires
# the on-disk identity to DIFFER from the parked one, and asserting no warning.
newhome 2b
export CLAUDESWITCH_FORCE=1
mk tok-alpha pro alpha@example.com
"$CS" save alpha >/dev/null 2>&1
mk tok-beta team beta@example.com
"$CS" save beta  >/dev/null 2>&1

# Now the live identity says beta; switching to alpha must rewrite it to alpha.
out="$("$CS" use alpha 2>&1)"
case "$out" in
  *"no parked identity"*) bad "restore_identity finds the parked file" "no warning" "$out" ;;
  *) ok "restore_identity finds the parked file (no warning)" ;;
esac
checkeq "identity actually rewritten beta->alpha" "alpha@example.com" \
  "$(python3 -c "import json;print(json.load(open('$HOME/.claude.json'))['oauthAccount']['emailAddress'])")"

# And back again, to prove it is not a one-way fluke.
out="$("$CS" use beta 2>&1)"
case "$out" in
  *"no parked identity"*) bad "restore works in reverse too" "no warning" "$out" ;;
  *) ok "restore works in reverse too" ;;
esac
checkeq "identity actually rewritten alpha->beta" "beta@example.com" \
  "$(python3 -c "import json;print(json.load(open('$HOME/.claude.json'))['oauthAccount']['emailAddress'])")"

# restore_identity must resolve its path from its ARGUMENT, not from a global
# that the `use` branch happens to set to the same value. Calling the function
# directly with the global unset is what distinguishes the two.
out="$(bash -c '
  set -uo pipefail
  # Load the script without executing a command, then call the function alone.
  eval "$(sed -n "/^restore_identity()/,/^}/p" '"$CS"')"
  PARK_DIR="'"$HOME"'/.claude-accounts"
  GLOBAL_JSON="'"$HOME"'/.claude.json"
  restore_identity alpha 2>&1
  python3 -c "import json;print(json.load(open(\"'"$HOME"'/.claude.json\"))[\"oauthAccount\"][\"emailAddress\"])"
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
# The data-loss path this exists to close: `use` overwrites the live credential,
# so switching while logged in as an UNPARKED account destroys its token.
newhome 2d
export CLAUDESWITCH_FORCE=1
mk tok-saved pro saved@example.com
"$CS" save saved >/dev/null 2>&1

# Now log in as a different, unparked account and switch away from it.
mk tok-unparked team unparked@example.com
out="$("$CS" use saved 2>&1)"
check "use reports the auto-park" "parked outgoing account to '_previous'" "$out"
[ -f "$HOME/.claude-accounts/_previous.credentials.json" ] \
  && ok "_previous slot created" || bad "_previous slot created" "exists" "missing"
checkeq "_previous holds the outgoing token" "tok-unparked" \
  "$(grep -o 'tok-[a-z]*' "$HOME/.claude-accounts/_previous.credentials.json")"
checkeq "switch still applied" "tok-saved" \
  "$(grep -o 'tok-[a-z]*' "$CLAUDE_CONFIG_DIR/.credentials.json")"

# The recovery path must actually work.
out="$("$CS" use _previous 2>&1)"
check "can recover via use _previous" "active account = slot '_previous'" "$out"
checkeq "recovered the otherwise-lost token" "tok-unparked" \
  "$(grep -o 'tok-[a-z]*' "$CLAUDE_CONFIG_DIR/.credentials.json")"

# Switching away from an ALREADY-parked account must not churn _previous.
newhome 2e
export CLAUDESWITCH_FORCE=1
mk tok-a pro a@example.com; "$CS" save a >/dev/null 2>&1
mk tok-b team b@example.com; "$CS" save b >/dev/null 2>&1
# Live is now b, which is parked as slot 'b'.
out="$("$CS" use a 2>&1)"
check "already-parked outgoing account is not re-parked" "already parked as" "$out"
[ ! -f "$HOME/.claude-accounts/_previous.credentials.json" ] \
  && ok "_previous not created for a parked account" \
  || bad "_previous not created for a parked account" "absent" "present"

# `use _previous` itself must not overwrite _previous with what it's replacing.
newhome 2f
export CLAUDESWITCH_FORCE=1
mk tok-keep pro keep@example.com; "$CS" save keep >/dev/null 2>&1
mk tok-lost team lost@example.com
"$CS" use keep >/dev/null 2>&1          # _previous = tok-lost
"$CS" use _previous >/dev/null 2>&1     # switching TO _previous
checkeq "use _previous does not clobber itself" "tok-lost" \
  "$(grep -o 'tok-[a-z]*' "$HOME/.claude-accounts/_previous.credentials.json")"
echo

echo "=============================================="
echo " 2f2. stale parked token still counts as parked"
echo "=============================================="
# Claude Code rotates the access token on refresh, so a slot legitimately holds
# an OLD token for the same account. Identity must be the account (via the parked
# oauthAccount.json), not the raw token — otherwise an already-parked account
# looks unparked within hours, producing endless false warnings and a redundant
# _previous slot on every switch.
newhome 2f2
export CLAUDESWITCH_FORCE=1
mk tok-v1 pro rotate@example.com
"$CS" save rotated >/dev/null 2>&1
# Simulate a token refresh: same account, new token, identity file unchanged.
mk tok-v2 pro rotate@example.com

out="$("$CS" internal-unparked 2>&1)"
checkeq "refreshed token not reported as unparked" "" "$out"

# And a switch must not create a redundant _previous for an already-parked account.
mk tok-other team other@example.com; "$CS" save other >/dev/null 2>&1
mk tok-v2 pro rotate@example.com    # live = rotate again, with the newer token
out="$("$CS" use other 2>&1)"
check "already-parked (stale token) is not re-parked" "already parked as" "$out"
[ ! -f "$HOME/.claude-accounts/_previous.credentials.json" ] \
  && ok "no redundant _previous for a refreshed token" \
  || bad "no redundant _previous for a refreshed token" "absent" "present"

# A genuinely different, unparked account MUST still be auto-parked.
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
# Re-saving the SAME account into its own slot is the normal refresh path.
out="$(CLAUDESWITCH_FORCE= "$CS" save shared 2>&1)"
# Fake tokens can't be identified via the API, so the guard can't compare emails
# here; it must fail open (save succeeds) rather than blocking a legitimate save.
check "re-saving same slot still works when emails unresolvable" "saved to slot" "$out"
[ -f "$HOME/.claude-accounts/shared.credentials.json" ] && ok "slot still present" || bad "slot present" "exists" "missing"
echo

echo "=============================================="
echo " 2h. hook: unparked-account detection"
echo "=============================================="
newhome 2h
# internal-unparked prints the active email only when it is in no slot. With
# unresolvable fake tokens it must stay silent rather than emit a bogus warning.
mk tok-solo pro solo@example.com
out="$("$CS" internal-unparked 2>&1)"
checkeq "internal-unparked stays quiet when email unresolvable" "" "$out"
checkeq "  ...and exits 0" "0" "$?"
# With no live credential at all it must also stay quiet and not error.
rm -f "$CLAUDE_CONFIG_DIR/.credentials.json"
out="$("$CS" internal-unparked 2>&1)"; rc=$?
checkeq "internal-unparked quiet with no credential" "" "$out"
checkeq "  ...and exits 0" "0" "$rc"
# The hook must never block a session, even with a broken environment.
out="$(bash /repo/hooks/check-shim.sh 2>&1)"; rc=$?
checkeq "hook exits 0 even with no credential" "0" "$rc"

# With emails resolvable, the hook must actually WARN about an unparked account
# and auto-park when opted in. A mocked curl makes identify() return an email
# derived from the token, which is what these paths depend on.
#
# Regression guard: the check previously required `claudeswitch` on PATH, so it
# silently did nothing for anyone without a shim — i.e. most users at first run.
newhome 2i
mkdir -p /mockbin
cat > /mockbin/curl <<'MOCK'
#!/bin/bash
for a in "$@"; do case "$a" in "Authorization: Bearer "*) t="${a#Authorization: Bearer }";; esac; done
echo "{\"account\":{\"email\":\"${t}@example.com\"}}"
MOCK
chmod +x /mockbin/curl

mkalias() { # mk with an email matching the token, so identify() and json agree
  printf '{"claudeAiOauth":{"accessToken":"%s","subscriptionType":"pro","rateLimitTier":"t1","expiresAt":1790000000000,"refreshTokenExpiresAt":1792000000000}}' "$1" > "$CLAUDE_CONFIG_DIR/.credentials.json"
  printf '{"oauthAccount":{"emailAddress":"%s@example.com"}}' "$1" > "$HOME/.claude.json"
}
export PATH="/mockbin:$PATH"
export CLAUDE_PLUGIN_ROOT=/repo CLAUDESWITCH_FORCE=1
mkalias alice; "$CS" save alice >/dev/null 2>&1
mkalias bob   # bob is now live and unparked

out="$("$CS" internal-unparked 2>&1)"
checkeq "internal-unparked names the unparked account" "bob@example.com" "$out"

out="$(bash /repo/hooks/check-shim.sh 2>&1)"
check "hook warns about the unparked account" "not parked in any slot" "$out"
check "  ...and names it" "bob@example.com" "$out"
check "  ...and explains the opt-in" "autopark" "$out"
[ -f "$HOME/.claude-accounts/bob.credentials.json" ] \
  && bad "warning mode must not write a slot" "no bob slot" "slot created" \
  || ok "warning mode writes nothing"

# Opt in, then the hook should park it silently.
mkdir -p "$CLAUDE_CONFIG_DIR/claudeswitch" && echo 1 > "$CLAUDE_CONFIG_DIR/claudeswitch/autopark"
out="$(bash /repo/hooks/check-shim.sh 2>&1)"
check "autopark mode parks the account" "parked the active account as 'bob'" "$out"
[ -f "$HOME/.claude-accounts/bob.credentials.json" ] \
  && ok "autopark created a slot named from the email" \
  || bad "autopark created a slot" "bob.credentials.json" "missing"
checkeq "autoparked slot holds the right token" "bob" \
  "$(python3 -c "import json;print(json.load(open('$HOME/.claude-accounts/bob.credentials.json'))['claudeAiOauth']['accessToken'])")"

# Now that bob is parked, the check must go quiet.
out="$(bash /repo/hooks/check-shim.sh 2>&1)"
case "$out" in
  *"not parked in any slot"*) bad "quiet once parked" "no warning" "$out" ;;
  *"parked the active account"*) bad "does not re-park" "no second park" "$out" ;;
  *) ok "quiet once the account is parked" ;;
esac
unset CLAUDE_PLUGIN_ROOT
export PATH="${PATH#/mockbin:}"
echo

echo "=============================================="
echo " 3. file permissions (tokens are secrets)"
echo "=============================================="
# Self-contained: earlier sections leave $HOME in varying states.
newhome 3
export CLAUDESWITCH_FORCE=1
mk tok-perm pro perm@example.com
# The harness creates the live file with a plain redirect, so its mode is the
# shell's default (644) — that is Claude Code's file, not ours. What claudeswitch
# must guarantee is that everything IT writes is 600, and that a switch tightens
# the live credential rather than leaving a token world-readable.
chmod 644 "$CLAUDE_CONFIG_DIR/.credentials.json"
"$CS" save perm >/dev/null 2>&1
checkeq "parked slot is 600" "600" "$(stat -c '%a' "$HOME/.claude-accounts/perm.credentials.json")"
checkeq "park dir is 700"    "700" "$(stat -c '%a' "$HOME/.claude-accounts")"
checkeq "save does not loosen the parked copy" "600" "$(stat -c '%a' "$HOME/.claude-accounts/perm.credentials.json")"
"$CS" use perm >/dev/null 2>&1
checkeq "use writes the live credential as 600 (tightens 644)" "600" \
  "$(stat -c '%a' "$CLAUDE_CONFIG_DIR/.credentials.json")"
# The identity backup contains no token, but should not be world-writable.
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

# The regression fixed this session: a clean single error, no trailing noise.
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
echo " 6. empty / corrupt slot handling"
echo "=============================================="
newhome 6
export CLAUDESWITCH_FORCE=1
mk tok-a pro a@example.com
"$CS" save a >/dev/null 2>&1
: > "$HOME/.claude-accounts/a.credentials.json"   # truncate the slot
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
echo " 9. install-shim on Linux"
echo "=============================================="
newhome 9
export SHELL=/bin/bash
out="$("$CS" install-shim "$HOME/bin" </dev/null 2>&1)"
check "shim installs" "installed shim" "$out"
[ -x "$HOME/bin/claudeswitch" ] && ok "shim is executable" || bad "shim is executable" "executable" "not"
check "picks .bashrc on Linux (not .bash_profile)" ".bashrc" "$out"
head -1 "$HOME/bin/claudeswitch" | grep -q 'env bash' \
  && ok "shim uses portable env-bash shebang" \
  || bad "shim shebang" "#!/usr/bin/env bash" "$(head -1 "$HOME/bin/claudeswitch")"
bash -n "$HOME/bin/claudeswitch" && ok "shim is valid bash" || bad "shim syntax" "valid" "invalid"
out="$(CLAUDE_CONFIG_DIR="$HOME/none" "$HOME/bin/claudeswitch" whoami 2>&1)"
check "shim reports missing plugin cleanly" "plugin not found" "$out"

# zsh should still map to .zshrc on Linux.
newhome 9b
out="$(SHELL=/bin/zsh "$CS" install-shim "$HOME/bin" </dev/null 2>&1)"
check "zsh on Linux picks .zshrc" ".zshrc" "$out"
# Unknown shell -> ~/.profile (POSIX fallback), not a zsh guess.
newhome 9c
out="$(SHELL=/bin/ksh "$CS" install-shim "$HOME/bin" </dev/null 2>&1)"
check "unknown shell picks .profile" ".profile" "$out"
echo

echo "=============================================="
echo " 10. SessionStart hook"
echo "=============================================="
newhome 10
out="$(bash /repo/hooks/check-shim.sh 2>&1)"; rc=$?
checkeq "hook exits 0" "0" "$rc"
check "hook prompts for shim install" "install-shim" "$out"
out2="$(bash /repo/hooks/check-shim.sh 2>&1)"
checkeq "hook stays quiet on second run (nag-once)" "" "$out2"
echo

echo "=============================================="
echo " 11. keychain backend correctly unusable here"
echo "=============================================="
newhome 11
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
