#!/bin/bash
# Drive a headless REAPER on a virtual X display (see tools/reaper/README.md).
#   reaper.sh start            start Xvfb and REAPER (no-op when running)
#   reaper.sh stop             stop both
#   reaper.sh run FILE.lua     run a Lua file inside REAPER, print its output
#   reaper.sh eval 'CODE'      same for a snippet
#   reaper.sh shot [OUT.png]   screenshot of the virtual display
#   reaper.sh windows          titles of visible windows (error dialogs show up here)
#   reaper.sh test             run tests/reaper/*_test.lua
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PREFIX=${FME_REAPER_PREFIX:-/opt/fme-reaper}
APP=$PREFIX/REAPER
BRIDGE=${FME_BRIDGE:-/tmp/fme-reaper}
export DISPLAY=${FME_DISPLAY:-:99}
unset WAYLAND_DISPLAY

die() { echo "reaper.sh: $*" >&2; exit 2; }

# A killed Xvfb leaves its socket behind and X clients then hang, hence the timeouts.
display_up() { timeout 2 xdotool getdisplaygeometry >/dev/null 2>&1; }

running() { [ -f "$BRIDGE/reaper.pid" ] && kill -0 "$(cat "$BRIDGE/reaper.pid")" 2>/dev/null; }

start() {
  running && return 0
  [ -x "$APP/reaper" ] || die "REAPER is not installed; run tools/reaper/install.sh"
  if ! display_up; then
    pkill -f "Xvfb $DISPLAY" 2>/dev/null
    rm -f "/tmp/.X${DISPLAY#:}-lock" "/tmp/.X11-unix/X${DISPLAY#:}"
    setsid Xvfb "$DISPLAY" -screen 0 1600x1000x24 -nolisten tcp </dev/null >/dev/null 2>&1 &
    for _ in $(seq 50); do display_up && break; sleep 0.1; done
    display_up || die "Xvfb did not start on $DISPLAY"
  fi
  rm -rf "$BRIDGE"; mkdir -p "$BRIDGE/inbox" "$BRIDGE/outbox"; echo 0 > "$BRIDGE/seq"
  printf 'dofile([[%s]])([[%s]],[[%s]])\n' "$ROOT/tools/reaper/bridge.lua" "$BRIDGE" "$ROOT" > "$APP/Scripts/__startup.lua"
  setsid "$APP/reaper" -nosplash -new </dev/null >"$BRIDGE/reaper.log" 2>&1 &
  echo $! > "$BRIDGE/reaper.pid"
  for _ in $(seq 300); do
    if [ -f "$BRIDGE/ready" ]; then
      close_nag; echo "REAPER $(cat "$BRIDGE/ready") on $DISPLAY"; return 0
    fi
    running || break
    sleep 0.1
  done
  echo "REAPER did not come up. Log:" >&2; tail -20 "$BRIDGE/reaper.log" >&2
  windows >&2
  exit 1
}

# An evaluation copy opens "About REAPER" with a short countdown; close it once
# it lets go so screenshots show the arrange view. A license avoids this.
close_nag() {
  local id _
  for _ in $(seq 30); do
    id=$(timeout 2 xdotool search --onlyvisible --name '^About REAPER' 2>/dev/null | head -1)
    [ -n "$id" ] && break; sleep 0.1
  done
  [ -n "$id" ] || return 0
  for _ in $(seq 100); do
    timeout 2 xdotool windowclose "$id" 2>/dev/null
    sleep 0.2
    timeout 2 xdotool search --onlyvisible --name '^About REAPER' >/dev/null 2>&1 || return 0
  done
}

stop() {
  running && kill "$(cat "$BRIDGE/reaper.pid")" 2>/dev/null
  pkill -f "Xvfb $DISPLAY" 2>/dev/null
  for _ in $(seq 50); do
    pgrep -f "$APP/reaper|Xvfb $DISPLAY" >/dev/null || break; sleep 0.1
  done
  pkill -9 -f "$APP/reaper|Xvfb $DISPLAY" 2>/dev/null
  rm -f "/tmp/.X${DISPLAY#:}-lock" "/tmp/.X11-unix/X${DISPLAY#:}"
  rm -f "$BRIDGE/reaper.pid"
  return 0
}

run() {
  local file=$1 timeout=${FME_TIMEOUT:-90} n
  [ -f "$file" ] || die "no such file: $file"
  start >/dev/null || exit 1
  n=$(flock "$BRIDGE/seq" bash -c 'n=$(( $(cat "$1") + 1 )); echo $n > "$1"; echo $n' _ "$BRIDGE/seq")
  cp "$file" "$BRIDGE/inbox/$n.lua.part" && mv "$BRIDGE/inbox/$n.lua.part" "$BRIDGE/inbox/$n.lua"
  for _ in $(seq $((timeout * 10))); do
    if [ -f "$BRIDGE/outbox/$n.status" ]; then
      cat "$BRIDGE/outbox/$n.out"; [ -s "$BRIDGE/outbox/$n.out" ] && echo
      [ "$(cat "$BRIDGE/outbox/$n.status")" = ok ]; return
    fi
    check_errors
    running || { echo "REAPER exited. Log:" >&2; tail -20 "$BRIDGE/reaper.log" >&2; return 1; }
    sleep 0.1
  done
  echo "timed out after ${timeout}s; open windows:" >&2; windows >&2
  return 1
}

# A script error opens a modal "ReaScript Error" window that stalls REAPER, and
# the bridge with it. Save a screenshot of the message, close it and say where.
check_errors() {
  local id
  id=$(timeout 2 xdotool search --onlyvisible --name '^ReaScript Error' 2>/dev/null | head -1)
  [ -n "$id" ] || return 0
  local shot=$BRIDGE/error-$(date +%s%N).png
  import -window root "$shot" 2>/dev/null
  echo "ReaScript Error window (screenshot: $shot)" >&2
  timeout 2 xdotool windowclose "$id" 2>/dev/null
}

windows() {
  local id
  display_up || return 0
  for id in $(timeout 5 xdotool search --onlyvisible --name '' 2>/dev/null); do
    printf '%s\t%s\n' "$id" "$(xdotool getwindowname "$id" 2>/dev/null)"
  done
}

cmd=${1:-}; shift || true
case $cmd in
  start) start ;;
  stop) stop ;;
  restart) stop; sleep 0.5; start ;;
  run) run "${1:?usage: reaper.sh run FILE.lua}" ;;
  eval)
    tmp=$(mktemp --suffix=.lua); printf '%s\n' "${1:?usage: reaper.sh eval CODE}" > "$tmp"
    run "$tmp"; status=$?; rm -f "$tmp"; exit $status ;;
  shot)
    out=${1:-$BRIDGE/shot.png}; import -window root "$out" && echo "$out" ;;
  windows) windows ;;
  test)
    start >/dev/null || exit 1
    failed=0
    for t in "$ROOT"/tests/reaper/*_test.lua; do
      if out=$(run "$t" 2>&1); then echo "ok    ${t#$ROOT/}${out:+  ($out)}"
      else echo "FAIL  ${t#$ROOT/}"; echo "$out" | sed 's/^/      /'; failed=1; fi
    done
    exit $failed ;;
  *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
