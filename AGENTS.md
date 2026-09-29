# Notes for agents

- `MIDI Editor/` is the ReaPack category folder. ReaPack installs it to `Scripts/Fluent MIDI Editor/MIDI Editor/`. The launcher scripts find `lib/` next to themselves; never hardcode `GetResourcePath()` paths.
- Keep the action file names stable: REAPER's Actions list, shortcuts and the double-click override point at them.
- Item extstate keys keep the `LiveMIDIRepeat*` prefix of earlier builds so repeats in saved projects stay recognised. Do not rename them.
- Local development: link `MIDI Editor/` into REAPER's `Scripts` folder as `Fluent MIDI Editor (dev)` (on Windows, `New-Item -ItemType Junction`) and load its Open action once. Edits take effect the next time the action runs. Never edit the ReaPack-installed copy; syncing overwrites it.
- Run `python -m unittest discover -s tests` before handing work back. Drawing and gestures are checked by hand in REAPER.
- Release: bump `@version` in `Fluent MIDI Editor - Open.lua`, run `python tools/make_index.py`, commit, tag `v<version>`, push the commit and the tag. The index points at files under that tag, so an untagged index breaks installs.
- `dev/` holds local REAPER harness scripts and is excluded from git.
