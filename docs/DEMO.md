# Recording the demo

A 20-second recording is the highest-conversion asset on the README, because the
value here is inherently visual: same terminal, one command, different account.
This file is the script so the recording is short and re-shootable.

You have to run this yourself — it needs your real accounts.

## What the viewer must understand in 20 seconds

1. Two accounts are parked.
2. One command switches between them.
3. No browser, no `/login`.

Nothing else. Resist showing `install-shim`, platform support, or the guards —
every extra second loses viewers.

## Setup before recording

```bash
# Both accounts parked and NOT expired. Check first:
claudeswitch list          # both slots must resolve real emails, not "(lookup failed)"
```

If a slot shows `(lookup failed — offline or token expired)`, that slot's refresh
token has expired. `/login` as that account and `claudeswitch save <name>` again
before recording, or the demo shows an error.

Then make the terminal presentable:

```bash
clear
# ~80x24 is ideal. Larger than that and the text is unreadable when embedded.
# Zoom the font up — GitHub renders this small.
```

Hide anything you don't want public: your shell prompt may show a directory,
hostname, or git branch. The demo shows **real email addresses** — if that matters,
create throwaway slots named `work`/`personal` first, or accept it (they are your
own accounts, and a demo without real emails is less convincing).

## The script

Type these live — do not paste. Pauses matter more than speed; the viewer needs a
beat to read each result.

```bash
# 1. Establish the situation (2s pause after)
claudeswitch list

# 2. The switch — this is the moment (3s pause; let the output land)
claudeswitch use work

# 3. Prove it took effect (2s pause)
claudeswitch whoami

# 4. And back, to show it is bidirectional and instant
claudeswitch use personal
claudeswitch whoami
```

Stop recording there. Do not add a summary card or outro.

## Recording it

**asciinema** (sharp text, small file, but needs a player — GitHub will not
autoplay it inline):

```bash
brew install asciinema agg          # macOS; on Linux use your package manager
asciinema rec demo.cast             # Ctrl-D to stop
agg demo.cast docs/demo.gif         # convert to GIF for inline embedding
```

**Direct GIF** (simpler, plays inline on GitHub — usually the better trade):

- macOS: [Kap](https://getkap.co) or QuickTime → convert with `ffmpeg`
- Linux: [Peek](https://github.com/phw/peek)

```bash
# If you have a video file, convert with a sane palette and size:
ffmpeg -i demo.mov -vf "fps=12,scale=900:-1:flags=lanczos,split[s0][s1];\
[s0]palettegen[p];[s1][p]paletteuse" -loop 0 docs/demo.gif
```

Keep it **under ~2 MB** and **under 25 seconds**. Large GIFs stall on mobile and
GitHub will not preview very large files.

## Then

Uncomment the embed near the top of [README.md](../README.md):

```markdown
![claudeswitch demo](docs/demo.gif)
```

Check it renders on the GitHub page itself, not just in a local preview — relative
paths behave differently once pushed.

Re-record whenever the output format of `list`, `use`, or `whoami` changes. A demo
showing output that no longer matches the tool is worse than no demo.
