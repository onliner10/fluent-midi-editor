# Notes for agents

- `MIDI Editor/` is the ReaPack category folder. ReaPack installs it to `Scripts/Fluent MIDI Editor/MIDI Editor/`. The launcher scripts find `lib/` next to themselves; never hardcode `GetResourcePath()` paths.
- Keep the action file names stable: REAPER's Actions list, shortcuts and the double-click override point at them.
- Item extstate keys keep the `LiveMIDIRepeat*` prefix of earlier builds so repeats in saved projects stay recognised. Do not rename them.
- Local development: link `MIDI Editor/` into REAPER's `Scripts` folder as `Fluent MIDI Editor (dev)` (on Windows, `New-Item -ItemType Junction`) and load its Open action once. Edits take effect the next time the action runs. Never edit the ReaPack-installed copy; syncing overwrites it.
- UI: read `docs/design.md` first. Panels are built only from `ui:` components and tokens in `MIDI Editor/lib/theme.lua`; never raw ImGui widgets, style pushes, cursor moves or colour literals. `tests/test_design.py` and `tests/reaper/layout_test.lua` enforce this; add new controls to the theme, the doc and the layout test.
- Run `python -m unittest discover -s tests` before handing work back. Drawing and gestures are checked by hand in REAPER.
- Cloud sessions (and Linux with `tools/reaper/install.sh`) have a headless REAPER with ReaImGui. The unittest run then includes `tests/reaper/*_test.lua` inside it. To check drawing or gestures yourself, open the editor through `tools/reaper/reaper.sh run`, drive it with `xdotool` on `DISPLAY=:99` and look at `reaper.sh shot`. See `tools/reaper/README.md`. The user still checks feel by hand on Windows.
- Branches: work lands on `dev`; `main` is what everyone installs. `.github/workflows/release.yml` publishes both and commits `index.xml` to main itself; never hand-edit the index.
- Dev builds: every push to `dev` that changes `MIDI Editor/` is tagged `v<version>-dev.<n>` and published as a pre-release. `@version` on dev is the next release (plain, e.g. `0.11.0`); CI adds `-dev.<n>`. ReaPack offers dev builds only to people who enable pre-releases for the package.
- Release: merge `dev` into main with `@version` set to the new version, optionally with notes in `docs/releases/v<version>.md`. CI tags `v<version>`, creates the release and regenerates the index (the stable version plus newer dev builds). Then bump `@version` on dev to the next release, or dev builds stop.
- `python tools/make_index.py` rebuilds the index from the tags (`git fetch --tags` first); each version points at files under its own tag.
- `dev/` holds local REAPER harness scripts and is excluded from git.
