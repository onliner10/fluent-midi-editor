# Notes for agents

- `MIDI Editor/` is the ReaPack category folder. ReaPack installs it to `Scripts/Fluent MIDI Editor/MIDI Editor/`. The launcher scripts find `lib/` next to themselves; never hardcode `GetResourcePath()` paths.
- Keep the action file names stable: REAPER's Actions list, shortcuts and the double-click override point at them.
- Item extstate keys keep the `LiveMIDIRepeat*` prefix of earlier builds so repeats in saved projects stay recognised. Do not rename them.
- Local development: link `MIDI Editor/` into REAPER's `Scripts` folder as `Fluent MIDI Editor (dev)` (on Windows, `New-Item -ItemType Junction`) and load its Open action once. Edits take effect the next time the action runs. Never edit the ReaPack-installed copy; syncing overwrites it.
- Run `python -m unittest discover -s tests` before handing work back. Drawing and gestures are checked by hand in REAPER.
- Cloud sessions (and Linux with `tools/reaper/install.sh`) have a headless REAPER with ReaImGui. The unittest run then includes `tests/reaper/*_test.lua` inside it. To check drawing or gestures yourself, open the editor through `tools/reaper/reaper.sh run`, drive it with `xdotool` on `DISPLAY=:99` and look at `reaper.sh shot`. See `tools/reaper/README.md`. The user still checks feel by hand on Windows.
- Release: bump `@version` in `Fluent MIDI Editor - Open.lua`, optionally add notes in `docs/releases/v<version>.md`, and push to main. `.github/workflows/release.yml` then tags `v<version>` and creates the GitHub release. Only after the tag exists, run `python tools/make_index.py`, commit and push: the index points at files under that tag, so an untagged index breaks installs.
- `dev/` holds local REAPER harness scripts and is excluded from git.
