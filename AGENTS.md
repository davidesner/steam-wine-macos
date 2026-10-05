# Instructions for coding agents

You are setting up **Windows Steam and Direct3D 11 games on an Apple Silicon
Mac** using free components. Follow this file exactly. `SKILL.md` is the
reference for *why*; this file is the procedure.

Read `SKILL.md` before troubleshooting anything. It documents four hard
requirements and five commonly-believed myths that are **false** - acting on
those myths is how people waste hours here.

---

## Procedure

### 1. Preflight

```sh
uname -m          # must be arm64
sw_vers           # macOS 13+ (verified on 26.5)
/usr/bin/arch -x86_64 /usr/bin/true && echo "rosetta ok"
df -h /           # need ~15GB free: ~2GB stack + Steam + games
```

If Rosetta is missing, `install.sh` installs it (asks for a password).
If not Apple Silicon, **stop** - this stack is Rosetta-dependent.

### 2. Install

```sh
./scripts/install.sh
```

Downloads ~500MB and needs **sudo once**, for GStreamer. It is idempotent -
safe to re-run, and it skips anything already present.

The user must enter their password when prompted. If running non-interactively
and sudo is unavailable, `./scripts/install.sh --no-sudo` skips GStreamer, but
tell the user plainly that intro videos will not decode and many games will
hang on the splash screen.

Honour `STEAM_WINE_ROOT` (default `~/steam-wine`) and `STEAM_WINE_PREFIX`
(default `$STEAM_WINE_ROOT/prefix`) if the user wants different locations.

### 3. Verify

```sh
./scripts/verify.sh
```

Every check must pass before continuing. Each failure names its consequence.
If anything fails, fix that before launching - do not proceed and hope.

### 4. Launch and hand over

```sh
./scripts/launch-steam.sh
```

Then **tell the user these three things** - they are interactive steps you
cannot do for them:

1. **A dialog saying "Unexpected Transport Error" is expected on first run.**
   They must choose **"Continue Anyway"**. Never "Restart Steam" - that just
   re-enters the loop.
2. They log into Steam normally. With Steam Guard it needs **phone approval**.
3. Once logged in, they install and launch games **from the Steam library as
   normal**. Nothing special is needed per game.

---

## Rules while operating this stack

Violating these causes failures that look like something else entirely:

- **Never `kill -9` Steam.** SIGKILL stops it flushing its session token, forcing
  a fresh login with phone approval. Use `pkill -f Steam.exe` (SIGTERM).
- **Never point a second Wine version at an existing prefix.** This corrupts it
  irreparably. Symptom: `steamwebhelper` crash-looping and Steam never logging
  in. The fix is to rebuild the prefix, *not* to debug the engine.
- **Count processes with `ps -Ao comm | grep -ci 'steam\.exe'`.** Steam
  relaunches itself as lowercase `steam.exe` after bootstrap, so
  `pgrep -f "Steam.exe"` reports **zero while it is running perfectly**.
- **Do not delete a game's `.mp4` intro files** to skip a hang. The game then
  waits forever for a video-finished callback and hangs harder. Fix the H.264
  decode instead (GStreamer).
- **Do not add DXMT's `nvapi64.dll`/`nvngx.dll`.** They import dxgi+winemetal and
  become a footgun; `install.sh` removes them deliberately.
- **Do not "fix" things by disabling Steam's GPU acceleration** or setting the
  prefix to Windows 7. Both are myths; see `SKILL.md`.

## Diagnosing a user's existing broken setup

Run `./scripts/verify.sh <engine-dir> <prefix-dir>` against it first. Then map
the symptom:

| Symptom | Cause | Action |
|---|---|---|
| webhelper crash-loops; never logs in | corrupted prefix, or missing `libgnutls` | check gnutls first, else rebuild prefix |
| Win32 dialogs render with no text | missing `libfreetype` | add support dylibs |
| "Failed to initialize graphics / DirectX 11" | DXMT not loading | engine `d3d11.dll` must be ~5MB, not ~385KB |
| black screen after publisher logos | H.264 decode failing | install GStreamer, link its libs |
| `Failed to create metal view ... no exported symbols` | wrong engine | must export `macdrv_view_*_metal_*` |

Useful logs:

```
<prefix>/drive_c/Program Files (x86)/Steam/logs/connection_log.txt   login
<prefix>/drive_c/Program Files (x86)/Steam/logs/cef_log.txt          webhelper
<prefix>/drive_c/users/<u>/AppData/LocalLow/<pub>/<game>/output_log.txt
```

## Reporting back

State plainly what works and what does not. In particular:

- DX12 titles are **not** supported by this stack (DXMT is D3D11/10 only).
- Kernel-level anti-cheat will **never** work under Wine.
- Performance costs two translation layers (Rosetta 2 + D3D11→Metal); suggest
  lowering in-game settings.

Do not claim a game works until the user confirms it renders and is playable.
