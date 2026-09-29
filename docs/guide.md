# Fluent MIDI Editor — user guide

A separate, dockable window inside REAPER, inspired by the
[Ableton Live](https://www.ableton.com/en/live-manual/12/editing-midi/) piano roll.
Fluent MIDI Editor is an independent project, not affiliated with Ableton or Cockos.
It edits notes and modulation in clips: position, length, velocity, CC curves,
steps, zoom and call & response between tracks.
There is no quantizer, legato, scales, or tools that generate or transform phrases.

## Opening

Run **Fluent MIDI Editor - Open** from the Actions list with MIDI clips selected,
or assign it a shortcut (Actions → select the action → Add shortcut).
Running it again while the window is open focuses it on the selected clips.

**Installing and opening the editor change neither the native editor nor double-click.**
The optional action **Fluent MIDI Editor - Set as default editor** makes double-clicking
a MIDI clip open this editor. **Fluent MIDI Editor - Restore default editor** restores the
remembered double-click action, unless you changed it later in preferences.
Both are also in the editor's **Options** menu.

Requires REAPER 7 and ReaImGui with API 0.10 (ReaPack). SWS is optional;
it enables previewing single notes through the matching track's instrument,
without arming tracks.

## Multiple tracks

1. In the arrange view, select MIDI clips on two or three tracks.
2. Run Fluent MIDI Editor. The selected clips appear on a shared timeline.
3. Click a track name in the left panel to choose where **new** notes and pastes go.
4. Existing notes can be selected and edited on all visible tracks together.

Each clip has its own color. Low velocity darkens a note, high velocity brightens it;
selected notes have a white outline. A single note fills the row height.
When notes from different tracks overlap at the same pitch, they split the row
into colored parts: click the right part to select or drag that note.
Right-clicking where notes overlap opens a picker by track name and velocity.
The selection rectangle also tells these parts apart. The MIDI stays at the same
pitch and time — the split only affects how notes are drawn.
One gesture across several tracks is one Undo step in REAPER.

## Phrase length, repeats and loop

In the left panel, below the track list, the **Phrase length** field applies to the clip
selected on the left; its name is shown above the field. Enter a number of bars, e.g. `4`,
`0.5` or `1,5`, and press **Enter**. **Escape** cancels the input.
The **÷2 / ×2** buttons halve or double the phrase right away.

This is the length of the **editable phrase**, not of the whole clip with repeats. For example,
a 4-bar clip can contain a 2-bar phrase played twice: the field shows
`2`, and the grid shows the original and the repeat. Entering `4` in the same field
pulls the second half into the phrase — from then on both halves are edited independently.
No Glue or extra button is needed.

**Loop: all clips** fits the loop range to the whole visible group, repeats included,
whenever the length changes. For CALL 2 bars / RESPONSE 4 bars
the shared loop covers 4 bars. The Loop button keeps its previous state.
One **Ctrl+Z** undoes the length, repeats and loop range together.
Other open phrases keep their length.

Turn on **Repeat phrase** on a shorter clip to make it play until the end of the longest
clip in the current group. Existing REAPER repeats (Loop source) are
detected automatically. Opening the editor alone changes neither clips nor MIDI.
Above the grid each track has a labeled strip: the first pass is **editable**,
later ones are **read-only**. These strips only show length; they have no drag handles.
One cursor runs across the shared timeline.

Repeated notes have a **dashed outline**, and their velocity shows an empty marker
and a dashed line. Note brightness still reflects velocity only.
Changing the original updates all repeats when you release the mouse.
Copies cannot be selected, moved, deleted or have their velocity changed in Fluent MIDI Editor;
all of these operations are done on the first pass.

Repeats created by **Repeat phrase** are real MIDI clips
sharing one source in the arrange view. Existing source loops stay inside
their clip until the phrase length changes for the first time.
They keep playing after the editor is closed and persist when the project is saved.
Turning **Repeat phrase** off removes only the copies the editor manages.
Opening such a copy in Fluent MIDI Editor takes you to its original.
Shortening or lengthening the phrase rebuilds the copies; **Ctrl+D** duplicates the edited
notes and may lengthen the original, reducing the number of automatic repeats accordingly.

With repeat on, lengthening the phrase pulls the next repeats into editing.
Without repeat, lengthening adds empty space. Shortening hides notes past the end but keeps
them in the MIDI source — they reappear when you lengthen it again. Editing visible notes
does not delete the hidden part and does not automatically restore the previous length.
Use **Ctrl+D** to duplicate content.

Repeats end no later than the next independent clip on the same
track. The last pass may be shorter. The limit is 256 repeats per phrase.
Every change in Fluent MIDI Editor fits the copies to the currently open clips.
Old clips that were moved or replaced in the arrange view do not set the end of the new group.
Selecting and opening alone never write anything: existing repeats show
the actual playback in the arrange view. If they belong to a different set of clips, a
notice appears; applying the current **Phrase length** fits them to the current clips
in one Undo step. The next note edit does the same fit in its own Undo step.

After a length change, repeats reach only the end of the longest phrase
in the group. Two 2-bar phrases give 2 bars with no extra repeats;
2- and 4-bar phrases give 4 bars with the shorter one repeated. When editing a single
clip, the entered length also sets its end. The previous range is not
kept. Other clips sharing the old source stay unchanged.
The whole operation can be undone with one **Ctrl+Z**.

## Modulation stored in the clip

Below the piano roll there is a **Modulation** panel. The arrow, or a click
on its title, collapses it to a single bar that shows the number and names of lanes
in the clip. Drag the handle above the panel to change its height; double-click
the handle to collapse the panel. Its state and height are remembered. A clip without
modulation takes only the bar with buttons and a hint.

Select a clip on the left, then:

- **+ CC**: pick a controller number and MIDI channel.
- **+ VST parameter**: click the button, then move a knob in the plugin window
  on the same track. A lane named after the plugin and parameter appears. Clicking
  the button again or pressing Escape cancels the capture.
- The list above the graph switches between the active clip's parameters.
- **Curve / Steps** changes the drawing mode. Steps use the note grid.

Capturing creates a **Parameter modulation → Link from MIDI** connection
in REAPER and picks an unused CC. For the next clip on the same track
it reuses the earlier Fluent MIDI Editor mapping. An existing parameter envelope,
LFO or foreign link makes the capture refuse; the editor shows a message.
Parameters in the track's main FX chain are supported, JSFX included.
Take FX, Input FX, FX containers and the master track are not captured at the moment.

The curve gestures follow the FilterShaper XL editor:

| Gesture on the modulation graph | Action |
| --- | --- |
| Single click on empty space | Add point |
| Double-click an existing point | Delete point |
| Drag a point | Change time and value; a selected group moves together |
| Drag a segment | Bend the curve |
| Click a point | Toggle sharp / smooth |
| Shift + click a point | Soften: Hard → Medium → Soft |
| Ctrl + click on empty space | Add a Soft point |
| Rectangle on empty space | Select points |
| Shift while dragging / Snap button | Temporary / permanent snap to grid |
| Alt / Ctrl+Alt while dragging a point | Constrain movement to value / time |
| Right-click a point | Choose Hard, Medium, Soft, Step or delete |
| Ctrl+A / Delete while the lane has focus | Select / delete points |
| Escape | Cancel the gesture |

The slider below the graph sets the exact value of a single selected
point. One finished gesture is one Undo step. The first pass is
editable, and repeats are drawn with a dashed line.

**The curve, its points and their names are stored in the clip's MIDI source.**
REAPER plays back plain CC; the Fluent MIDI Editor window can be closed. Copying a clip
in the arrange view carries the modulation, repeats play it back, and pooled MIDI
shares its edits. Saving the project keeps the points and the FX mapping.
The CC → parameter link belongs to the track: after moving a clip to another
track, that track's FX needs a matching mapping. The editor shows when the
link is missing; the CC data stays in the clip.

**Ctrl+D** also copies CC within the duplicated phrase range. With a time
selection it works without notes too. **Ctrl+C / Ctrl+V** carries the notes and the
active clip's CC from that range; positions adapt to the target take's resolution
and playback rate. Dragging, deleting and **Ctrl+X**
on notes affect notes only. To duplicate a whole phrase with its modulation, use Ctrl+D
or copy the clip in the arrange view.

This is **7-bit MIDI CC** modulation, i.e. 128 values; curves are sampled
up to 96 times per quarter note. It is not an LFO generator running at audio
rate. Existing CC can be edited in the lane. Native shapes other than linear
or step need the **Import current CC as points** button, which
replaces their interpolation with segments between points. When the editor detects
a mismatch between the stored points and CC changed from outside, it also
offers the import. Pitch bend, MPE and 14-bit CC have no dedicated editor.

## Cheat sheet

| Gesture / shortcut | Action |
| --- | --- |
| Double-click empty cell / note | Add / delete note |
| B | Draw; dragging creates more notes |
| Drag a note / edge | Position and pitch / start or end |
| Rectangle with left or right button | Select notes and a time range; right works while drawing too |
| Shift + drag on the ruler | Select a time range on all tracks |
| Shift + click | Add a note to or remove it from the selection |
| Ctrl+A / Ctrl+Shift+A | All notes / invert selection |
| Ctrl+D | Duplicate the selected time including silence; the copy becomes selected |
| Ctrl + drag | Copy notes with the mouse |
| Ctrl+C / X / V | Copy / cut / paste into the active clip at the cursor |
| Arrows | Move notes by grid step / semitone |
| Shift+↑ / ↓ | Transpose by an octave |
| Shift+← / → | Change length |
| Alt + drag the middle of a note | Velocity |
| Drag a velocity marker | Velocity; a selected group keeps its differences |
| Velocity slider | One value for selected notes, or the value for new notes |
| F / 0 | Fold to used pitches / mute notes |
| Ctrl+1 / 2 / 3 / 4 | Finer / coarser grid / triplets / snap |
| Alt while resizing an edge | Temporarily invert snap |
| Ctrl + wheel | Zoom time around the pointer |
| Alt + wheel | Row height |
| Shift + wheel | Scroll time |
| Middle mouse button | Pan the view |
| Drag the ruler | Horizontal: scroll, vertical: zoom |
| Z / X | Show selection / all clips |
| Space / Ctrl+L | Transport / loop playback of the selection |
| Ctrl+Z / Ctrl+Shift+Z | Undo / redo in REAPER |
| Escape | Cancel a gesture or clear the selection |

Snap pulls the absolute position of a dragged note or its edge to the grid.
After a free move and turning snap back on, the next move removes the offset
from the grid. Changing only the pitch keeps the time position.

Ctrl+D uses the selected time range, including silence on both sides. Without a time
selection it uses the span of the selected notes, extended to the active grid lines.
Repeated Ctrl+D duplicates the phrase at the same interval. Regular clips, including
ones with a single source loop enabled, grow when the copy extends past their end.

## Writing and limits

- Notes go straight into the active takes; they are written when you release the mouse.
- Note editing keeps CC, pitch bend, sysex, text, flags and note-off velocity.
  The modulation lane writes only the chosen CC and its points. Ctrl+D and
  range copy carry CC as described above; plain note moves
  do not move CC, MPE or notation.
- If a clip changes from outside during a gesture, the editor rejects the stale write.
  A lock on one of the edited clips stops the whole shared write.
- A clip that loops its source several times shows the first pass for editing
  and the rest as read-only repeats. Changing the phrase length
  lets you pull repeats into independent editing.
- Pooled MIDI keeps sharing its source as in REAPER. Changing
  two clips from the same pool at once is rejected; edit only one of them.
- The clipboard is internal and shared by the clips in the current window.
- No Chance or MPE editing.

## Development

`python -m pip install -r requirements-dev.txt`, then
`python -m unittest discover -s tests` runs the Lua logic through `lupa`.
Drawing and gestures are checked by hand in REAPER.

### Drawing and performance

The layout of overlapping notes is recomputed after notes or clip boundaries change.
Selection and velocity changes reuse the same geometry.
The piano roll and hit testing share one list of notes visible at the current zoom;
long notes starting off-screen are still visible and clickable.
The overview merges marks that fall on the same pixels, and dashed repeat outlines
are clipped before drawing. Undo, external edits and length changes
refresh the cache. REAPER object validation still runs every frame.
