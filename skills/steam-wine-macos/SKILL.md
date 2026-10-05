---
name: steam-wine-macos
description: Set up, repair or diagnose Windows Steam and Direct3D 11 games running under Wine on Apple Silicon macOS, using only free and open-source components (WineCX + DXMT + GStreamer). Achieves what commercial compatibility layers do, at no cost. Use when the user wants to run Windows Steam or a Windows game on a Mac, or when an existing Wine/Steam setup misbehaves - black game window, steamwebhelper crash-looping or "not responding", Steam never logging in, "Failed to initialize graphics / DirectX 11", games hanging on the intro video, or DXMT errors about metal view or cross-process swapchain.
---

# Windows Steam + D3D11 games on Apple Silicon

A verified-working stack built entirely from free and open-source components -
achieving what commercial compatibility layers do, at no cost - plus the failure
modes that look like something else. Every rule here was established by
elimination on a real machine; the misleading symptoms are called out explicitly.

## The stack

| Layer | Choice | Why this specifically |
|---|---|---|
| Engine | **WineCX 24.0.7** (via Sikarugir Engines) | Only free build exporting the Metal symbols DXMT needs |
| Renderer | **DXMT 0.74+** (D3D11 → Metal) | Wine's own D3D11 cannot create a device for many games |
| Video | **GStreamer 1.28.7** | H.264 intro movies; without it Unity games hang on the splash |
| Support libs | 94 dylibs from Gcenx wine-stable | Engine ships none; without `libgnutls` Steam cannot log in |

x86_64 under Rosetta 2 throughout.

## Quick start

```sh
scripts/install.sh        # one-time; downloads ~500MB, needs sudo for GStreamer
scripts/launch-steam.sh   # start Steam, then launch games from the library
scripts/verify.sh         # check every invariant / diagnose a broken install
```

`verify.sh` takes `<engine-dir> <prefix-dir>` or reads `STEAM_WINE_ROOT` /
`STEAM_WINE_PREFIX`. Run it first whenever something is wrong - it checks all
four hard requirements below and names the consequence of each failure.

## The four hard requirements

Get any one wrong and it fails in a way that points somewhere else.

### 1. The engine must export the Metal symbols

DXMT needs these exported from `winemac.drv`:

```
macdrv_view_create_metal_view
macdrv_view_get_metal_layer
macdrv_view_release_metal_view
```

Most Wine builds **hide them** - Gcenx `wine-stable` and `wine-staging` both do.
DXMT then fails with `Failed to create metal view, it seems like your Wine has
no exported symbols needed by DXMT`.

DXMT's own documentation states the requirement as *"a FOSS CrossOver Wine 24+
built from the sources is sufficient"* - i.e. a Wine built from CodeWeavers'
published LGPL sources. The `WS12WineCX24.0.7_7` engine from Sikarugir Engines
is such a build, which is why this stack uses it.

> The widely-shared recipe *Gcenx wine-staging + DXMT* therefore **cannot work
> as published**. If a user is following that, this is why.

Check: `strings <bundle>/lib/wine/x86_64-unix/winemac.so | grep macdrv_view_create_metal_view`

### 2. DXMT's `-builtin` build goes in the Wine tree, never the prefix

Replace `d3d11.dll`, `dxgi.dll`, `d3d10core.dll` in
`wswine.bundle/lib/wine/{x86_64,i386}-windows/`, plus `winemetal.so` in
`x86_64-unix/`. **Both architectures** - leaving a stale DXMT 32-bit `dxgi.dll`
while removing its `winemetal.dll` makes every 32-bit component fail with
`Library dxgi.dll not found`.

Installing it in the prefix's `system32` with `=n` overrides **does not work**
(`could not load d3d11.dll (80029c4a)`). Upstream only ships the `-builtin`
variant.

Consequence: DXMT applies to every process on that engine, Steam included.
That is fine - see Myths.

### 3. Support dylibs must be in `wswine.bundle/lib/`

Wine's unix libs resolve `@loader_path/../../` → `wswine.bundle/lib/`, while
`wineserver` resolves to the engine's parent. Put them in **both**.

| Missing | Symptom |
|---|---|
| `libgnutls` | **Steam cannot log in.** `secure connections will not be available` |
| `libfreetype` | Win32 dialogs render **with no text** - blank buttons only |
| `libinotify` | Engine won't start: `Library not loaded: @rpath/libinotify.0.dylib` |

### 4. A prefix must never be run by a second Wine version

The highest-cost failure. A prefix touched by two Wine builds reaches a state no
engine rebuild repairs:

- `steamwebhelper` crash-loops, new PID every ~10-15s
- Steam never logs in; `[Logged Off, 0, 0] [U:1:0]`
- Endless "Steamwebhelper is not responding"

**If the webhelper crash-loops, rebuild the prefix. Do not debug the engine.**
A fresh prefix fixed this instantly: 7 healthy webhelpers, 0 restarts.

## Myths - all false

| Claim | Reality |
|---|---|
| DXMT breaks Steam's CEF webhelper | No. They coexist on a clean prefix; crash-looping was prefix corruption |
| Launching from Steam breaks DXMT (`cross-process swapchain not supported`) | No. That error is from Steam's own CEF, not the game. Library launches work |
| Disable Steam's GPU acceleration | No. The setting persists and makes things worse |
| Set the prefix to Windows 7 | No. Windows 10 (build 19045), no special flags |
| Steam needs `-cef-disable-gpu` / `-no-cef-sandbox` | No. Plain `Steam.exe`, no flags |

## Troubleshooting

**Webhelper crash-loops / Steam never logs in** → check `libgnutls` first (no
TLS = no login). Otherwise the prefix is corrupt: rebuild it.

**"Unexpected Transport Error (0x3008)"** → choose **Continue Anyway**. Normal
on first start. Never "Restart Steam" - that re-enters the loop.

**Game: "Failed to initialize graphics / DirectX 11"** → DXMT not loading.
`d3d11.dll` in the engine must be ~5 MB (DXMT), not ~385 KB (builtin), and
`winemetal.so` must exist.

**Game hangs black after publisher logos** → H.264 decode failing. Check the
Unity log for `WindowsVideoMedia error 0xc00d36bb`; link GStreamer libs into
`wswine.bundle/lib/`.
**Do not delete the `.mp4` files** - the game then waits forever for a
video-finished callback and hangs harder.

**Steam logged out after a crash** → something used `kill -9`. SIGKILL stops
Steam flushing its session token. Always `pkill -f Steam.exe` (SIGTERM).

**A game needs OpenGL instead** → check it shipped GL shaders. Unity titles
built D3D-only fail `-force-glcore` with `shaders will not be available`.

### Logs

```
<prefix>/drive_c/Program Files (x86)/Steam/logs/connection_log.txt   login
<prefix>/drive_c/Program Files (x86)/Steam/logs/cef_log.txt          webhelper
<prefix>/drive_c/users/<u>/AppData/LocalLow/<pub>/<game>/output_log.txt
```

Healthy game log:

```
Direct3D: Version: Direct3D 11.0 [level 11.1]
          Renderer: Apple M<n>
Received stats and achievements from Steam
LoadSceneCoroutine: currentScene.IsLoaded == true
```

**Counting processes:** Steam relaunches itself as lowercase `steam.exe` after
bootstrap. `pgrep -f "Steam.exe"` reports **zero while it runs fine**. Use
`ps -Ao comm | grep -ci 'steam\.exe'`.

## Limits

- Verified: Unity D3D11 title, launched from the Steam library, start to gameplay.
- Verified: a prefix built from scratch by `wineboot` plus a plain Steam install
  reaches a working Steam login screen - 4+ healthy webhelpers, zero restart
  loops, zero library errors. **Nothing beyond the four components above is
  required** - no commercial software, no pre-existing prefix.
- Untested: DX12 (needs D3DMetal/GPTK and *its* patched Wine), controllers, multiplayer.
- Impossible: kernel-level anti-cheat.
- Two translation layers (Rosetta 2 + D3D11→Metal) cost performance; lower settings.

## Licensing

Every component is free and redistributable: Wine and DXMT are LGPL/MIT,
GStreamer is LGPL, and the Sikarugir engine is built from CodeWeavers' publicly
published LGPL sources. No proprietary component is used and no commercial
licence is circumvented. Apple's Game Porting Toolkit is deliberately excluded,
since its EULA targets developer evaluation rather than general use.
