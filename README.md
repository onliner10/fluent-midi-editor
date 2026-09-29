# Fluent MIDI Editor

**Finally, a MIDI editor for REAPER that feels good.**

A dockable piano roll for REAPER, inspired by Ableton's. Select MIDI clips on
several tracks and edit them together on one timeline: bass against kick,
call against response. No setup, no custom actions to wire up first.

<!-- demo GIF goes here -->

> **Beta.** It is tested on one setup and has automated tests, but it has not met
> your projects yet. Please [report what breaks](https://github.com/onliner10/fluent-midi-editor/issues).

## What it does

- **Several tracks at once.** Clips from different tracks share one grid, each in its own color. One gesture across tracks is one Undo step.
- **Phrases and repeats.** Set a phrase length in bars (`2`, `0.5`, `1.5`), halve or double it, and let a short phrase repeat to the end of the longest one. Repeats are real, pooled REAPER clips that keep playing after the editor is closed.
- **Modulation inside the clip.** Draw CC curves or steps, or move a knob in a plugin on the track to capture that parameter. The curve lives in the clip, so copying the clip carries it.
- **Fast editing.** Ctrl+D duplicates the selected time including silence, Alt+drag sets velocity, F folds to used pitches, Ctrl+wheel zooms around the pointer.
- **Native Undo, native MIDI.** Everything is written straight into REAPER's takes. Nothing needs to keep running.

Deliberately not included: quantize, legato, scales, and phrase generators.
It aims to make everyday editing pleasant, not to replace every tool REAPER has.

## Install

1. Install [ReaPack](https://reapack.com) if you do not have it.
2. In REAPER: **Extensions → ReaPack → Import repositories…**, paste
   ```
   https://github.com/onliner10/fluent-midi-editor/raw/main/index.xml
   ```
3. **Extensions → ReaPack → Browse packages**, search for **Fluent MIDI Editor** and install it.
   Also install **ReaImGui** (from the default ReaTeam Extensions repository) if you do not have it.
4. Optional: **SWS** lets you preview notes through the track's instrument.

Requires REAPER 7 and ReaImGui 0.10 or later. Windows, macOS and Linux should work;
so far it has been tested on Windows.

## Use

Select MIDI clips, then run **Fluent MIDI Editor - Open** from the Actions list
(give it a shortcut). Your native MIDI editor and double-click stay as they are.
If you want double-click to open this editor instead, run
**Fluent MIDI Editor - Set as default editor**; **Restore default editor** undoes it.

The full [user guide](docs/guide.md) covers every gesture and shortcut.

## Development

```
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests
```

## License

[MIT](LICENSE). Not affiliated with Ableton or Cockos.
