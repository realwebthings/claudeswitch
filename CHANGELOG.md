# Changelog

Notable changes per release. This tool handles OAuth credentials, so anything
affecting where tokens are stored or how a switch behaves is called out explicitly.

## 2.0.5

- Fix: "Two Claude accounts" → "Multiple Claude accounts" in banner and README.

## 2.0.4

- Show warning before killing Claude Code sessions on `use`.

## 2.0.3

- `use` now prompts to kill running Claude Code sessions instead of refusing.
  Answers `y` to kill gracefully (SIGTERM, then SIGKILL after 5s) and proceed.
  `CLAUDESWITCH_FORCE=1` skips the prompt.

## 2.0.2

- Install banner now shows detailed quick start steps and all commands.

## 2.0.1

- Install script shows a banner with commands and quick start after install.

## 2.0.0

- **Remove python3 dependency entirely.** All JSON parsing replaced with
  `grep`/`sed`/`date`. Only requires `bash`, `curl`, and `security` (macOS).
- Remove `install-shim` command — replaced with `update` (re-runs `install.sh`).
- Remove dead plugin-only internal commands (`internal-unparked`, `internal-autopark`).

## 1.9.0

- Move plugin-only files (`hooks/`, `skills/`, `.claude-plugin/`) to `_plugin-backup/`.
- Add `VERSION` file as single source of truth for releases.
- Fix `install-shim` shim body (was pointing to plugin cache paths).
- Fix `install.sh`: guard `python3` check, add `2>/dev/null` to `uname`, add fish shell case.

## 1.8.0

- Direct install via `install.sh` — one curl command, no plugin required.
- GitHub Actions release workflow: auto-tags and publishes on version bump.
- Shim auto-installs itself on first session where safe (existing PATH directory).
- Fix path traversal in `rm` — slot-name validation now runs on all commands.
- Slot names starting with `-` are rejected.
- Parked identity files now mode 600.
- CI: Debian, Ubuntu, Alpine, Fedora + shellcheck on every push.
- Added SECURITY.md and CHANGELOG.md.

## 1.7.0

- `use` parks the outgoing account to `_previous` before switching.
- `save` refuses to overwrite a slot holding a different account (needs `CLAUDESWITCH_FORCE=1`).
- Unparked-account detection at session start.
- "Already parked" judged by account identity, not raw token.

## 1.6.0

- Linux and WSL support via file backend (`~/.claude/.credentials.json`).
- Atomic writes under `umask 077`.
- Docker-based test suite.
- Windows native best-effort support.

## 1.0.0 – 1.5.0

- Initial release: save, use, list, whoami, rm against the macOS Keychain.
- `install-shim` for out-of-session use.
- `/claudeswitch:help` troubleshooting skill.
