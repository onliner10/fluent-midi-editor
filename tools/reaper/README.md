# Headless REAPER

Linux-only tooling that runs a real REAPER with ReaImGui on a virtual X display,
so the editor can be tested without a desktop. Locally it works in WSL or any
Ubuntu 24.04.

In Claude Code cloud sessions the environment provides it. Its setup script:

```bash
curl -fsSL https://raw.githubusercontent.com/onliner10/fluent-midi-editor/main/tools/cloud-setup.sh | bash -s -- --force
```

It needs Custom network access with `www.reaper.fm` and `codeberg.org` plus the
default list, and optionally `FME_REAPER_LICENSE_B64` (below). The
SessionStart hook in `.claude/settings.json` only installs Python test dependencies.

```bash
bash tools/reaper/install.sh      # once; apt packages, REAPER, ReaImGui (root or sudo)
bash tools/reaper/reaper.sh test  # tests/reaper/*_test.lua
```

## Driving REAPER

`reaper.sh start` launches Xvfb on `:99` and a portable REAPER in
`/opt/fme-reaper/REAPER`, whose `Scripts/__startup.lua` loads `bridge.lua`. The
bridge runs Lua files you hand it inside REAPER:

| Command | |
| :- | :- |
| `reaper.sh run FILE.lua` | run a file, print what it `print`s; exit 1 on error |
| `reaper.sh eval 'CODE'` | the same for a snippet |
| `reaper.sh shot [OUT.png]` | screenshot of the whole display |
| `reaper.sh windows` | visible window titles |
| `reaper.sh stop` / `restart` | |

Jobs see `ROOT` (the repository) and `reaper`. A job that returns a function
keeps running: the function is called every defer cycle until it returns true,
which lets a job wait for the editor's own deferred loop. `tests/reaper/support.lua`
has helpers for building clips, opening the editor and waiting.

Mouse and keyboard go through `xdotool` with `DISPLAY=:99`, for example
`xdotool mousemove 600 360 mousedown 1 mousemove 700 360 mouseup 1`. Take a
screenshot first to find coordinates.

A script error opens a modal "ReaScript Error" window that stalls REAPER.
`run` closes it and prints the path of a screenshot showing the message.

With `FME_REAPER_LICENSE_B64` set (base64 of your `reaper-license.rk`),
`install.sh` registers REAPER. Without it REAPER runs as an evaluation copy and
`start` closes the evaluation reminder.
