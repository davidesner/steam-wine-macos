# steam-wine-macos

Run the **Windows Steam client and Direct3D 11 games on Apple Silicon macOS**
using only free and open-source components. Achieves what commercial
compatibility layers do, at no cost.

```sh
scripts/install.sh        # one-time setup (~500MB, sudo needed for GStreamer)
scripts/launch-steam.sh   # start Steam, then launch games from the library
scripts/verify.sh         # check every invariant / diagnose a broken install
```

**[SKILL.md](SKILL.md) is the real documentation** - the stack, the four hard
requirements, the myths, and troubleshooting. Read it before changing anything.

## What this is

A Claude Code skill plus three scripts, capturing a working configuration that
took a long debugging session to find. The value is less in the scripts than in
knowing *which* component versions work together and what the misleading failure
symptoms actually mean.

| Layer | Choice |
|---|---|
| Engine | WineCX 24.0.7 (via Sikarugir Engines) |
| Renderer | DXMT 0.74 (D3D11 → Metal) |
| Video | GStreamer 1.28.7 (H.264 intro movies) |
| Support libs | 94 dylibs from Gcenx wine-stable 11.0 |

Verified on macOS 26.5 / Apple M4 with a Unity D3D11 title, launched normally
from the Steam library - including a from-scratch prefix build, so **nothing
beyond the four components above is needed**.

## Using it as a Claude Code skill

Make it discoverable so Claude loads it automatically when you hit a Wine/Steam
problem:

```sh
# from inside this repo
mkdir -p ~/.claude/skills
ln -s "$(pwd)" ~/.claude/skills/steam-wine-macos
```

Then ask Claude things like *"my Steam webhelper keeps crashing under Wine"* or
*"set up Windows Steam on this Mac"* and it will apply this knowledge.

## Layout

```
SKILL.md              the guide (stack, requirements, myths, troubleshooting)
scripts/install.sh    builds engine + DXMT + GStreamer + prefix + Steam
scripts/launch-steam.sh
scripts/verify.sh     checks all invariants, names the consequence of each failure
```

## Configuration

Both scripts honour:

- `STEAM_WINE_ROOT` - install location (default `~/steam-wine`)
- `STEAM_WINE_PREFIX` - Wine prefix (default `$STEAM_WINE_ROOT/prefix`)

Keep **one prefix per Wine version**. Never point a different Wine build at an
existing prefix - that is the single most destructive mistake with this stack,
and `SKILL.md` explains why.

## License

MIT - see [LICENSE](LICENSE).

The components this installs keep their own licences: Wine and DXMT are
LGPL/MIT, GStreamer is LGPL, and the Sikarugir engine is built from CodeWeavers'
publicly published LGPL sources. Nothing proprietary is bundled or required.
