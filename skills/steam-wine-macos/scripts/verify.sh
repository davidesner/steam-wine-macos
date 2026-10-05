#!/bin/zsh
# Check every invariant that this stack depends on.
# Run against a live install to confirm it is healthy, or to diagnose a broken one.
#
#   ./verify.sh                                  # checks $HOME/steam-wine
#   STEAM_WINE_ROOT=... STEAM_WINE_PREFIX=... ./verify.sh
#   ./verify.sh <engine-dir> <prefix-dir>        # explicit paths

ENGINE_DIR="${1:-${STEAM_WINE_ROOT:-$HOME/steam-wine}/engine}"
PREFIX="${2:-${STEAM_WINE_PREFIX:-${STEAM_WINE_ROOT:-$HOME/steam-wine}/prefix}}"
BUNDLE="$ENGINE_DIR/wswine.bundle"

PASS=0; FAIL=0
ok()   { printf "  \033[32mPASS\033[0m  %s\n" "$1"; PASS=$((PASS+1)); }
bad()  { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=$((FAIL+1)); }
note() { printf "        %s\n" "$1"; }

echo
echo "Engine: $BUNDLE"
echo "Prefix: $PREFIX"
echo

echo "[engine]"
if [[ -x "$BUNDLE/bin/wine" ]]; then
  ok "wine binary present - $("$BUNDLE/bin/wine" --version 2>/dev/null | head -1)"
else
  bad "wine binary missing"
fi

if strings "$BUNDLE/lib/wine/x86_64-unix/winemac.so" 2>/dev/null \
   | grep -q 'macdrv_view_create_metal_view'; then
  ok "Metal symbols exported (DXMT requirement)"
else
  bad "Metal symbols MISSING - this engine cannot work with DXMT"
fi

echo
echo "[support libraries]"
for l in libgnutls libfreetype libinotify; do
  if ls "$BUNDLE/lib/"$l* >/dev/null 2>&1; then
    ok "$l"
  else
    bad "$l missing"
    case $l in
      libgnutls)   note "-> no TLS: Steam will NOT be able to log in" ;;
      libfreetype) note "-> Win32 dialogs will render with no text" ;;
      libinotify)  note "-> engine will fail to start" ;;
    esac
  fi
done

echo
echo "[DXMT]"
D="$BUNDLE/lib/wine/x86_64-windows/d3d11.dll"
if [[ -f "$D" ]]; then
  SZ=$(stat -f%z "$D" 2>/dev/null || stat -c%s "$D")
  if (( SZ > 3000000 )); then
    ok "x86_64 d3d11.dll is DXMT ($SZ bytes)"
  else
    bad "x86_64 d3d11.dll is Wine builtin ($SZ bytes) - games will fail graphics init"
  fi
else
  bad "d3d11.dll missing"
fi
I="$BUNDLE/lib/wine/i386-windows/d3d11.dll"
if [[ -f "$I" ]]; then
  SZ=$(stat -f%z "$I" 2>/dev/null || stat -c%s "$I")
  (( SZ > 3000000 )) && ok "i386 d3d11.dll is DXMT" || bad "i386 d3d11.dll is builtin (arch mismatch)"
fi
[[ -f "$BUNDLE/lib/wine/x86_64-unix/winemetal.so" ]] \
  && ok "winemetal.so present" || bad "winemetal.so missing - DXMT cannot initialise"

# nvapi64.dll imports dxgi + winemetal. Harmless while those exist, but if
# winemetal is ever removed it makes EVERY process fail to start.
if ls "$BUNDLE/lib/wine/x86_64-windows/nvapi64.dll" >/dev/null 2>&1; then
  if [[ -f "$BUNDLE/lib/wine/x86_64-windows/winemetal.dll" ]]; then
    ok "nvapi64.dll present, imports satisfied by winemetal.dll"
  else
    bad "nvapi64.dll present but winemetal.dll missing - every process will fail to start"
    note "-> rm nvapi64.dll nvngx.dll, or reinstall DXMT fully"
  fi
else
  ok "no nvapi64.dll"
fi

echo
echo "[video]"
if [[ -d /Library/Frameworks/GStreamer.framework ]]; then
  ok "GStreamer.framework installed"
  MISS=0
  for L in libgstvideo-1.0.0.dylib libgstaudio-1.0.0.dylib libgstreamer-1.0.0.dylib \
           libglib-2.0.0.dylib libgobject-2.0.0.dylib libgstbase-1.0.0.dylib libgsttag-1.0.0.dylib; do
    [[ -e "$BUNDLE/lib/$L" ]] || { MISS=$((MISS+1)); }
  done
  (( MISS == 0 )) && ok "GStreamer libs linked into engine" \
                  || { bad "$MISS GStreamer libs not linked"; note "-> H.264 intros fail; games hang on splash"; }
else
  bad "GStreamer.framework not installed - intro videos will not decode"
fi

echo
echo "[prefix]"
if [[ -f "$PREFIX/system.reg" ]]; then
  ok "prefix exists"
  grep -a '#arch' "$PREFIX/system.reg" 2>/dev/null | head -1 | sed 's/^/        /'
else
  bad "prefix missing or not initialised"
fi
if [[ -f "$PREFIX/drive_c/Program Files (x86)/Steam/Steam.exe" ]]; then
  ok "Steam installed in prefix"
else
  bad "Steam not installed in prefix"
fi
# DXMT must not also be shadowing from inside the prefix
for d in system32 syswow64; do
  if [[ -f "$PREFIX/drive_c/windows/$d/winemetal.dll" ]]; then
    SZ=$(stat -f%z "$PREFIX/drive_c/windows/$d/winemetal.dll" 2>/dev/null)
    note "note: $d/winemetal.dll present ($SZ bytes) - inert, Wine prefers builtins"
  fi
done

echo
echo "[runtime]"
S=$(ps -Ao comm | grep -ci 'steam\.exe')
W=$(ps -Ao comm | grep -ci steamwebhelper)
echo "        steam.exe=$S  steamwebhelper=$W"
if (( S > 0 )); then
  (( W >= 3 )) && ok "webhelper healthy ($W processes)" \
               || note "webhelper low ($W) - may still be starting, or crash-looping"
  LOG="$PREFIX/drive_c/Program Files (x86)/Steam/logs/connection_log.txt"
  if [[ -f "$LOG" ]]; then
    if grep -aE "^\[$(date +%Y-%m-%d)" "$LOG" 2>/dev/null | grep -aq 'Logged On.*processing complete'; then
      ok "Steam logged in today"
    else
      note "no login recorded today"
    fi
  fi
else
  note "Steam not running"
fi

echo
printf "  %d passed, %d failed\n\n" "$PASS" "$FAIL"
(( FAIL == 0 ))
