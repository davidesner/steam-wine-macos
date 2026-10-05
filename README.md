# steam-wine-macos

Run the **Windows Steam client and Direct3D 11 games on Apple Silicon macOS**
using only free and open-source components. Achieves what commercial
compatibility layers do, at no cost.

## Why this exists

Getting Windows Steam working on an Apple Silicon Mac is genuinely painful. Most
guides give up and point you at CrossOver, which is good software and worth
paying for if you want support. But every piece needed to do it for free already
exists and is open source: Wine, DXMT, GStreamer.

The catch is that nobody tells you *which* versions work together. The most
widely-shared free recipe cannot work at all, because those Wine builds hide a
symbol the renderer needs. Several failures point confidently at the wrong
component, so you end up rebuilding the thing that was never broken.

I wanted my daughter to be able to play her favourite game. Getting there took a
long evening of dead ends that all looked like something else. This repository
is that evening, compressed into a setup that runs in about fifteen minutes, so
nobody has to repeat it.

Verified on macOS 26.5 / Apple M4 with a Unity D3D11 title, launched normally
from the Steam library - including a from-scratch prefix build, so nothing
beyond the components below is needed.

---

## One command

**With a coding agent** (Claude Code, Codex, Cursor, …) - paste this prompt:

```
Set up Windows Steam and D3D11 gaming on this Mac by following
https://github.com/davidesner/steam-wine-macos - clone it, read AGENTS.md,
and do exactly what it says.
```

The agent reads [AGENTS.md](AGENTS.md), runs the install, verifies it, and hands
you the interactive steps it cannot do for you (one dialog, then your Steam
login).

**Without an agent:**

```sh
git clone https://github.com/davidesner/steam-wine-macos
cd steam-wine-macos/skills/steam-wine-macos
./scripts/install.sh && ./scripts/verify.sh && ./scripts/launch-steam.sh
```

Takes ~15 minutes, downloads ~500MB, and asks for your password once (GStreamer
installs system-wide). Then log in and launch games from the Steam library as
normal.

> On first launch Steam shows **"Unexpected Transport Error"**. Choose
> **"Continue Anyway"** - never "Restart Steam".

---

## What it installs

| Layer | Choice | Role |
|---|---|---|
| Engine | WineCX 24.0.7 (via Sikarugir Engines) | The only free Wine build exporting the Metal symbols DXMT needs |
| Renderer | DXMT 0.74 | D3D11 → Metal; Wine's own D3D11 cannot create a device for many games |
| Video | GStreamer 1.28.7 | H.264 intro movies; without it games hang on the splash |
| Support libs | 94 dylibs from Gcenx wine-stable 11.0 | The engine ships none; without `libgnutls` Steam cannot log in |

Everything runs x86_64 under Rosetta 2. Nothing proprietary is bundled or
required.

## Requirements

- Apple Silicon Mac (Rosetta 2 - installed automatically if missing)
- macOS 13+ (verified on 26.5)
- ~15 GB free disk
- One `sudo` prompt, for GStreamer

## Commands

Run from `skills/steam-wine-macos/` (or from `~/.claude/skills/steam-wine-macos/`
once installed as a skill):

```sh
./scripts/install.sh        # one-time setup; idempotent, safe to re-run
./scripts/launch-steam.sh   # start Steam
./scripts/verify.sh         # health-check / diagnose a broken install
```

Both honour `STEAM_WINE_ROOT` (default `~/steam-wine`) and `STEAM_WINE_PREFIX`
(default `$STEAM_WINE_ROOT/prefix`).

`verify.sh` runs 14 checks and names the consequence of each failure - run it
first whenever something breaks. It also works against an existing setup:

```sh
./scripts/verify.sh /path/to/engine /path/to/prefix
```

## Documentation

- **[SKILL.md](skills/steam-wine-macos/SKILL.md)** - the real guide: the stack, four hard requirements,
  five debunked myths, troubleshooting. Read before changing anything.
- **[AGENTS.md](AGENTS.md)** - procedure and operating rules for coding agents.

Also usable as a Claude Code skill, so Claude applies this knowledge
automatically whenever you hit a Wine/Steam problem:

```sh
# from the repo root
mkdir -p ~/.claude/skills
ln -s "$(pwd)/skills/steam-wine-macos" ~/.claude/skills/steam-wine-macos
```

Or copy it, if you would rather not keep the repo around:

```sh
cp -R skills/steam-wine-macos ~/.claude/skills/
```

The skill directory is self-contained - `SKILL.md` plus its `scripts/` - so it
works standalone once installed.

## Scope

**Works:** the Steam client, D3D11/D3D10 games, launched from the Steam library.

**Does not work:** DX12 titles (DXMT is D3D11/10 only), and anything with
kernel-level anti-cheat - that will never work under Wine.

**Expect a performance cost** from two translation layers (Rosetta 2 and
D3D11→Metal). Lower in-game settings help.

## The part that is actually worth your time

The scripts are the easy bit. The value is in
[SKILL.md](skills/steam-wine-macos/SKILL.md): four requirements that are not
obvious and five things people widely believe about this stack that are simply
false. Acting on those myths is how an evening disappears.

The headline example: the most-shared free recipe, *Gcenx wine-staging + DXMT*,
**cannot work as published** - those Wine builds hide the Metal symbols DXMT
requires. If you have tried it and failed, that is why, and it was never
something you did wrong.

## License

MIT - see [LICENSE](LICENSE).

The components this installs keep their own licences: Wine and DXMT are
LGPL/MIT, GStreamer is LGPL, and the Sikarugir engine is built from CodeWeavers'
publicly published LGPL sources.
