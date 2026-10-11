#!/bin/zsh
# ---------------------------------------------------------------------------
# Windows Steam + D3D11 games on Apple Silicon macOS, using free components.
#
# Builds the stack documented in ../README.md:
#   WineCX 24.0.7 + DXMT 0.74 + GStreamer 1.28.7  (all free & open source)
#
# Why these exact pieces - every one was established by elimination, see README:
#   * The engine MUST export macdrv_view_*_metal_* from winemac.drv. DXMT needs
#     exported from winemac.drv; Gcenx wine-stable/staging hide those symbols.
#   * DXMT's "-builtin" build MUST live in the Wine tree, NOT in the prefix
#     as a native override - it will not load from system32.
#   * The Wine support dylibs (libgnutls, libfreetype, libinotify) MUST be in
#     wswine.bundle/lib/. Without libgnutls, Wine has no TLS and Steam cannot
#     log in at all. Without libfreetype, Win32 dialogs render with no text.
#   * GStreamer libs must be linked into the same lib/ or H.264 intro videos
#     fail to decode and Unity games hang on the splash.
#   * The prefix must be created by ONE Wine version and never run by another.
#     Mixing versions corrupts it; symptoms are a crash-looping steamwebhelper
#     and a Steam client that never logs in.
#
# Usage:  ./install.sh            full install
#         ./install.sh --no-sudo  skip GStreamer (no intro videos; games may hang)
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="${STEAM_WINE_ROOT:-$HOME/steam-wine}"
ENGINE_DIR="$ROOT/engine"
BUNDLE="$ENGINE_DIR/wswine.bundle"
PREFIX="${STEAM_WINE_PREFIX:-$ROOT/prefix}"
DXMT_DIR="$ROOT/dxmt"
CACHE="$ROOT/.cache"

ENGINE_URL="https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineCX24.0.7_7.tar.xz"
DXMT_URL="https://github.com/3Shain/dxmt/releases/download/v0.74/dxmt-v0.74-builtin.tar.gz"
DYLIB_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz"
GST_URL="https://gstreamer.freedesktop.org/data/pkg/osx/1.28.7/gstreamer-1.0-1.28.7-universal.pkg"
GST_SHA="529fdf4a4027d942e59b5b3564f6400adaa008f63ce5f3fed4ffe35d73911994"
STEAM_URL="https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"

DO_SUDO=1
[[ "${1:-}" == "--no-sudo" ]] && DO_SUDO=0

log()  { printf "\n==> %s\n" "$1"; }
step() { printf "    %s\n" "$1"; }
die()  { printf "\nERROR: %s\n" "$1" >&2; exit 1; }

# --- preflight -------------------------------------------------------------
log "Checking prerequisites"
[[ "$(uname -s)" == "Darwin" ]] || die "macOS only."
[[ "$(uname -m)" == "arm64" ]]  || step "WARNING: built for Apple Silicon; Intel is untested."
if /usr/bin/arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
  step "Rosetta 2: present"
else
  step "Rosetta 2 missing - installing (needs your password)"
  sudo softwareupdate --install-rosetta --agree-to-license
fi

mkdir -p "$CACHE" "$ROOT"

fetch() {  # fetch <url> <dest> ; cached
  local url="$1" dest="$2"
  if [[ -s "$dest" ]]; then step "cached: $(basename "$dest")"; return; fi
  step "downloading $(basename "$dest")"
  curl -fL --retry 3 --progress-bar -o "$dest" "$url" || die "download failed: $url"
}

# --- 1. engine -------------------------------------------------------------
log "Installing WineCX 24.0.7 engine"
if [[ -x "$BUNDLE/bin/wine" ]]; then
  step "already installed"
else
  fetch "$ENGINE_URL" "$CACHE/engine.tar.xz"
  mkdir -p "$ENGINE_DIR"
  tar -xJf "$CACHE/engine.tar.xz" -C "$ENGINE_DIR"
  [[ -x "$BUNDLE/bin/wine" ]] || die "engine extraction failed"
  step "installed: $(cat "$BUNDLE/version" 2>/dev/null)"
fi

# verify the Metal symbols DXMT requires - the whole reason for this engine.
# Not `grep -q`: it exits on first match, strings dies of SIGPIPE, and
# pipefail then reports the pipeline as failed even though the symbol exists.
if strings "$BUNDLE/lib/wine/x86_64-unix/winemac.so" 2>/dev/null \
   | grep -c 'macdrv_view_create_metal_view' >/dev/null; then
  step "Metal symbols present (required by DXMT)"
else
  die "engine lacks macdrv_view_*_metal_* symbols - DXMT cannot work with it"
fi

# --- 2. support dylibs -----------------------------------------------------
# The Sikarugir engine ships NO dylibs; it expects them from its wrapper app.
# Standalone we must supply them, or: no TLS (no Steam login) and no fonts.
log "Installing Wine support libraries (gnutls/freetype/inotify + deps)"
if [[ -e "$BUNDLE/lib/libgnutls.dylib" ]]; then
  step "already present"
else
  fetch "$DYLIB_URL" "$CACHE/wine-stable.tar.xz"
  rm -rf "$CACHE/winestable"; mkdir -p "$CACHE/winestable"
  tar -xJf "$CACHE/wine-stable.tar.xz" -C "$CACHE/winestable"
  SRC="$CACHE/winestable/Wine Stable.app/Contents/Resources/wine/lib"
  [[ -d "$SRC" ]] || die "could not find dylibs in wine-stable package"
  cp -n "$SRC"/*.dylib "$BUNDLE/lib/" 2>/dev/null || true
  cp -n "$SRC"/*.dylib "$ENGINE_DIR/" 2>/dev/null || true   # wineserver rpath is ../../
  step "installed $(ls "$BUNDLE/lib"/*.dylib | wc -l | tr -d ' ') dylibs"
fi
for l in libgnutls libfreetype libinotify; do
  ls "$BUNDLE/lib/"$l* >/dev/null 2>&1 || die "$l missing - Steam will not work"
done
step "verified: libgnutls, libfreetype, libinotify"

# --- 3. DXMT ---------------------------------------------------------------
log "Installing DXMT 0.74 (D3D11 -> Metal)"
if [[ ! -d "$DXMT_DIR/x86_64-windows" ]]; then
  fetch "$DXMT_URL" "$CACHE/dxmt.tar.gz"
  mkdir -p "$DXMT_DIR"
  tar -xzf "$CACHE/dxmt.tar.gz" -C "$DXMT_DIR" --strip-components=1
fi
# NOTE: the builtin variant goes in the WINE TREE. Do not put it in system32
# and do not set native overrides - it will fail to load.
cp "$DXMT_DIR/x86_64-windows/"*.dll "$BUNDLE/lib/wine/x86_64-windows/"
cp "$DXMT_DIR/i386-windows/"*.dll   "$BUNDLE/lib/wine/i386-windows/"
cp "$DXMT_DIR/x86_64-unix/winemetal.so" "$BUNDLE/lib/wine/x86_64-unix/"
# DXMT's nvapi stubs import dxgi + winemetal. They are harmless while DXMT is
# fully installed, but become a footgun if winemetal is ever removed: then
# EVERY process fails with "Library dxgi.dll not found". They are NVIDIA
# shims with no purpose on Apple hardware, so drop them.
rm -f "$BUNDLE/lib/wine/x86_64-windows/nvapi64.dll" \
      "$BUNDLE/lib/wine/x86_64-windows/nvngx.dll" \
      "$BUNDLE/lib/wine/i386-windows/nvapi.dll"
step "DXMT installed into engine tree (both architectures)"

# --- 4. GStreamer ----------------------------------------------------------
log "Installing GStreamer (H.264 decode for game intro videos)"
if [[ -d /Library/Frameworks/GStreamer.framework ]]; then
  step "framework already installed"
elif (( DO_SUDO )); then
  fetch "$GST_URL" "$CACHE/gstreamer.pkg"
  GOT=$(shasum -a 256 "$CACHE/gstreamer.pkg" | awk '{print $1}')
  [[ "$GOT" == "$GST_SHA" ]] || die "GStreamer checksum mismatch (got $GOT)"
  step "checksum verified against upstream"
  step "installing system-wide (needs your password)"
  sudo installer -pkg "$CACHE/gstreamer.pkg" -target /
else
  step "SKIPPED (--no-sudo): intro videos will not decode; games may hang"
fi
if [[ -d /Library/Frameworks/GStreamer.framework ]]; then
  GSTLIB=/Library/Frameworks/GStreamer.framework/Versions/1.0/lib
  n=0
  for lib in "$GSTLIB"/*.dylib; do
    N=$(basename "$lib")
    [[ -e "$BUNDLE/lib/$N" ]] || { ln -sf "$lib" "$BUNDLE/lib/$N"; n=$((n+1)); }
  done
  step "linked $n GStreamer libs into the engine"
fi

# --- 5. prefix -------------------------------------------------------------
# Created by this engine ONLY. Never run another Wine version against it.
log "Creating Wine prefix"
if [[ -f "$PREFIX/system.reg" ]]; then
  step "prefix already exists at $PREFIX"
else
  mkdir -p "$PREFIX"
  WINEPREFIX="$PREFIX" WINEARCH=win64 WINEDEBUG=-all \
    DYLD_FALLBACK_LIBRARY_PATH="$BUNDLE/lib:$ENGINE_DIR:/usr/lib" \
    "$BUNDLE/bin/wineserver" -k 2>/dev/null || true
  WINEPREFIX="$PREFIX" WINEARCH=win64 WINEDEBUG=-all \
    DYLD_FALLBACK_LIBRARY_PATH="$BUNDLE/lib:$ENGINE_DIR:/usr/lib" \
    "$BUNDLE/bin/wine" wineboot --init 2>/dev/null || true
  for i in {1..60}; do [[ -f "$PREFIX/system.reg" ]] && break; sleep 2; done
  [[ -f "$PREFIX/system.reg" ]] || die "prefix creation failed"
  step "prefix created at $PREFIX"
fi

# --- 6. Steam --------------------------------------------------------------
log "Installing Steam"
if [[ -f "$PREFIX/drive_c/Program Files (x86)/Steam/Steam.exe" ]]; then
  step "Steam already installed"
else
  fetch "$STEAM_URL" "$CACHE/SteamSetup.exe"
  WINEPREFIX="$PREFIX" WINEDEBUG=-all MVK_CONFIG_LOG_LEVEL=1 \
    DYLD_FALLBACK_LIBRARY_PATH="$BUNDLE/lib:$ENGINE_DIR:/usr/lib" \
    "$BUNDLE/bin/wine" "$CACHE/SteamSetup.exe" /S 2>/dev/null || true
  WINEPREFIX="$PREFIX" "$BUNDLE/bin/wineserver" -w 2>/dev/null || true
  [[ -f "$PREFIX/drive_c/Program Files (x86)/Steam/Steam.exe" ]] \
    || die "Steam install failed"
  step "Steam installed"
fi

log "Done"
cat <<EOF

  Engine : $BUNDLE  ($(cat "$BUNDLE/version" 2>/dev/null))
  Prefix : $PREFIX
  DXMT   : 0.74 (in engine tree)

  Start Steam with:   $(cd "$(dirname "$0")" && pwd)/launch-steam.sh

  First run: Steam self-updates (~300MB), then you log in. If you see
  "Unexpected Transport Error", choose "Continue Anyway" - NOT "Restart Steam".
  See ../README.md "Troubleshooting" before changing anything.

EOF
