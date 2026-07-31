# Changelog

Notable changes per release. This tool handles OAuth credentials, so anything
affecting where tokens are stored or how a switch behaves is called out
explicitly.

Versions refer to `.claude-plugin/plugin.json`. Update with
`/plugin update claudeswitch` (or `claude plugin update claudeswitch`), then reload
the window.

## 1.8.0 — unreleased

### Fixed

- **Path traversal in `rm`.** Slot-name validation ran only on `save`, so
  `claudeswitch rm '../somewhere/file'` deleted
  `../somewhere/file.credentials.json` — a file outside `~/.claude-accounts`.
  Validation now runs on `save`, `use`, and `rm`. `use` was not exploitable and no
  credentials could leak; exploiting it required running the command with a crafted
  argument. See [SECURITY.md](SECURITY.md#fixed-issues).
- Slot names starting with `-` are rejected. Such a name becomes a filename that
  looks like an option to `rm`, `find`, and `cp`.
- Parked identity files (`<name>.oauthAccount.json`) are now mode 600. They hold no
  token, but they do record an account email; previously they were 644.
- `restore_identity` resolved its path from a global that the `use` branch happened
  to set to the same value (shellcheck SC2318). It worked by luck and would have
  broken if called from anywhere else.
- An unquoted `$HOME` in `install-shim` was treated as a glob pattern (SC2295).

### Added

- CI: the Linux suite runs on Debian, Ubuntu, Alpine, and Fedora, plus shellcheck,
  on every push and PR. Alpine is included because BusyBox `find`/`stat`/`sed` is
  where non-portable shell breaks while still passing on Debian.
- [SECURITY.md](SECURITY.md): threat model, exactly what is stored where per
  platform, the single network call, and private vulnerability reporting.
- This changelog.

## 1.7.0

### Added

- **`use` parks the outgoing account.** Switching overwrites the live credential,
  so previously, switching while logged in as an unparked account destroyed its
  token. It now lands in a `_previous` slot — recover with
  `claudeswitch use _previous`.
- **`save` refuses to overwrite a slot holding a different account.** Re-saving the
  same account into its own slot is unchanged; repointing a slot at a different
  account requires `CLAUDESWITCH_FORCE=1`.
- **Unparked-account detection** at session start. If the active account is in no
  slot, you are told to park it, because a future `/login` would destroy it.
  Opt in to parking it automatically with
  `echo 1 > ~/.claude/claudeswitch/autopark`.

### Fixed

- "Already parked" is judged by **account**, not by raw token. Claude Code rotates
  the access token on refresh, so a slot legitimately holds a stale token for the
  same account — comparing tokens reported parked accounts as unparked within
  hours, producing false warnings and a redundant `_previous` on every switch.
- The session-start check located `claudeswitch` via `PATH`, so it silently did
  nothing before `install-shim` had been run — i.e. for most users at first run. It
  now uses the plugin's own `bin/`.
- `whoami` printed a spurious `(unparseable credential)` after a clean error, and
  exited 0 on failure.

## 1.6.0

### Added

- **Linux and WSL support.** Credential storage is now a pluggable backend: the
  macOS Keychain (via `security`) or `~/.claude/.credentials.json` with parked
  slots as sibling files in `~/.claude-accounts/`. Override detection with
  `CLAUDESWITCH_BACKEND=keychain|file`.
  - File writes go to a temp file in the same directory under `umask 077`, then an
    atomic `mv`, so an interrupted switch cannot leave a half-written credential
    and a token is never briefly world-readable.
  - Windows native is best-effort and **unverified**; if the token is not in a
    `.credentials.json` file, claudeswitch says so rather than pretending to
    switch. WSL is the tested path for Windows.
- A Docker-based test suite (`./test/run-docker.sh`) covering the file backend.

### Fixed

- Process detection also matches `claude-desktop` and `Claude.exe`, and falls back
  to `ps -W` where `pgrep` is unavailable (Git Bash).
- `install-shim` picks `~/.bashrc` on Linux rather than `~/.bash_profile`, which
  often does not exist there — appending to a file nothing sources looked like
  success while changing nothing.
- The generated shim uses `#!/usr/bin/env bash` for systems where bash is not at
  `/bin/bash` (NixOS, some BSDs).
- `set -u` no longer aborts when `HOME` is unset.

## 1.5.0 and earlier

- `1.5.0` — `install-shim` reliability; docs restructured around a four-step path;
  `/claudeswitch:help` troubleshooting skill.
- `1.4.x` — stale-version notice; dropped the assumption that the `claude` CLI is
  installed.
- `1.3.0` — first-session reminder to run `install-shim`.
- `1.2.0` — `install-shim`, so the command works outside Claude Code sessions
  (required, because switching accounts means Claude Code must be quit).
- `1.1.0` — install and author URLs corrected.
- `1.0.0` — initial release: save, use, list, whoami, rm against the macOS Keychain.
