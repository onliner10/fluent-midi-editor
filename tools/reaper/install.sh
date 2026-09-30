#!/bin/bash
# Install a headless REAPER for Linux x86_64 with ReaImGui, for tests and agents.
# Idempotent: a second run only checks what is there. Needs root or sudo for apt.
set -euo pipefail

REAPER_VERSION=${REAPER_VERSION:-7.81}
REAIMGUI_VERSION=${REAIMGUI_VERSION:-0.10.0.5}
PREFIX=${FME_REAPER_PREFIX:-/opt/fme-reaper}
APP=$PREFIX/REAPER
SUDO=; [ "$(id -u)" = 0 ] || SUDO=sudo

log() { echo "[reaper-install] $*"; }

packages=(xvfb xdotool imagemagick xz-utils curl ca-certificates fonts-dejavu-core
  libgtk-3-0t64 libgl1 libgl1-mesa-dri libegl1 libasound2t64)
missing=()
for p in "${packages[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
if [ ${#missing[@]} -gt 0 ]; then
  log "apt: ${missing[*]}"
  $SUDO apt-get update -qq
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq --no-install-recommends "${missing[@]}" >/dev/null
fi

if [ ! -x "$APP/reaper" ] || ! grep -qx "$REAPER_VERSION" "$PREFIX/.version" 2>/dev/null; then
  log "REAPER $REAPER_VERSION"
  file=reaper${REAPER_VERSION//./}_linux_x86_64.tar.xz
  tmp=$(mktemp -d)
  curl -fsSL "https://www.reaper.fm/files/${REAPER_VERSION%%.*}.x/$file" -o "$tmp/$file"
  tar -xJf "$tmp/$file" -C "$tmp"
  $SUDO rm -rf "$PREFIX"; $SUDO mkdir -p "$PREFIX"
  $SUDO cp -a "$tmp"/reaper_linux_x86_64/REAPER "$APP"
  echo "$REAPER_VERSION" | $SUDO tee "$PREFIX/.version" >/dev/null
  rm -rf "$tmp"
fi

# A reaper.ini next to the binary makes this a portable install: the resource
# path is $APP, so nothing lands in ~/.config and the tests start from known state.
if [ ! -f "$APP/reaper.ini" ]; then
  $SUDO tee "$APP/reaper.ini" >/dev/null <<'INI'
[REAPER]
splashstart=0
audioasync=0
linux_audio_mode=2
audiocloseinactive=1
autosaveint=0
autosavemode=0
showmaintrack=1
newprojdo=0
loadlastproj=0
lastproj=
verchk=0
vstpath=
lv2path_linux=;
clap_path_linux-x86_64=
INI
fi
# Your REAPER license: base64 of reaper-license.rk from your resource folder
# (Options > Show REAPER resource path). Without it REAPER runs as an evaluation
# copy and reaper.sh closes the reminder window.
if [ -n "${FME_REAPER_LICENSE_B64:-}" ]; then
  echo "$FME_REAPER_LICENSE_B64" | base64 -d | $SUDO tee "$APP/reaper-license.rk" >/dev/null
fi
$SUDO mkdir -p "$APP/UserPlugins" "$APP/Scripts"
$SUDO chmod -R a+rwX "$PREFIX"

# ReaImGui, as ReaPack would install it: the plugin plus the imgui.lua shim that
# require('imgui') loads. Codeberg first: cloud sessions cannot fetch release
# assets of GitHub repositories other than their own.
fetch() { curl -fsSL "$1" -o "$3.part" || curl -fsSL "$2" -o "$3.part"; mv "$3.part" "$3"; }
plugin=$APP/UserPlugins/reaper_imgui-x86_64.so
shim="$APP/Scripts/ReaTeam Extensions/API/imgui.lua"
if [ ! -f "$plugin" ] || [ ! -f "$shim" ] || ! grep -qx "$REAIMGUI_VERSION" "$PREFIX/.reaimgui" 2>/dev/null; then
  log "ReaImGui $REAIMGUI_VERSION"
  v=v$REAIMGUI_VERSION
  mkdir -p "$(dirname "$shim")"
  fetch "https://codeberg.org/cfillion/reaimgui/releases/download/$v/reaper_imgui-x86_64.so"     "https://github.com/cfillion/reaimgui/releases/download/$v/reaper_imgui-x86_64.so" "$plugin"
  fetch "https://raw.githubusercontent.com/cfillion/reaimgui/$v/shims/imgui.lua"     "https://codeberg.org/cfillion/reaimgui/raw/$v/shims/imgui.lua" "$shim"
  echo "$REAIMGUI_VERSION" > "$PREFIX/.reaimgui"
fi

log "ready: $APP/reaper"
