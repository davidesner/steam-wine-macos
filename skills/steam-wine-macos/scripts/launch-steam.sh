#!/bin/zsh
# Launch Windows Steam under WineCX 24 + DXMT on Apple Silicon.
# Launch your games normally from the Steam library once it is up.
set -euo pipefail

ROOT="${STEAM_WINE_ROOT:-$HOME/steam-wine}"
ENGINE_DIR="$ROOT/engine"
BUNDLE="$ENGINE_DIR/wswine.bundle"
PREFIX="${STEAM_WINE_PREFIX:-$ROOT/prefix}"

[[ -x "$BUNDLE/bin/wine" ]] || { echo "Engine missing - run install.sh first."; exit 1; }
[[ -d "$PREFIX" ]]          || { echo "Prefix missing - run install.sh first."; exit 1; }

STEAM_DIR="$PREFIX/drive_c/Program Files (x86)/Steam"
[[ -f "$STEAM_DIR/Steam.exe" ]] || { echo "Steam not installed - run install.sh first."; exit 1; }

# Only ONE Steam session may exist, or logins kick each other off.
# Use SIGTERM, never kill -9: SIGKILL loses the saved session token and you
# will have to log in again (including phone approval).
pkill -f steamwebhelper 2>/dev/null || true
pkill -if 'steam\.exe'  2>/dev/null || true
for i in {1..20}; do pgrep -if 'steam\.exe' >/dev/null || break; sleep 1; done
sleep 2

export WINEPREFIX="$PREFIX"
export WINEDEBUG="${WINEDEBUG:--all,err+all}"
export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-1}"   # silence MoltenVK spam
export DXMT_LOG_LEVEL="${DXMT_LOG_LEVEL:-error}"
export DYLD_FALLBACK_LIBRARY_PATH="$BUNDLE/lib:$ENGINE_DIR:/Library/Frameworks/GStreamer.framework/Versions/1.0/lib:/usr/lib"

cd "$STEAM_DIR"
LOG="${TMPDIR:-/tmp}/steam-wine.log"
echo "Starting Steam...  (log: $LOG)"
nohup "$BUNDLE/bin/wine" Steam.exe </dev/null >"$LOG" 2>&1 &
disown

echo "Waiting for Steam to come up..."
for i in {1..60}; do
  if [[ "$(ps -Ao comm | grep -ci steamwebhelper)" -ge 3 ]]; then
    echo "Steam UI is up."
    break
  fi
  sleep 2
done

cat <<'EOF'

If a dialog appears:
  "Unexpected Transport Error"      -> choose "Continue Anyway"
  "Steamwebhelper is not responding" -> "Restart steamwebhelper"
Never pick "Restart Steam" - it just re-enters the loop.

Then launch your game from the Steam library as normal.
EOF
