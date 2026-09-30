# Design system

Everything the editor draws in its panels comes from one file,
[`MIDI Editor/lib/theme.lua`](../MIDI%20Editor/lib/theme.lua): colours, spacing,
sizes and every control. Other files ask the theme for a control and never
decide how one looks. Tests enforce this, so a change that breaks the rules
fails `python -m unittest discover -s tests` before anyone sees it.

## Principles

The editor follows Apple's
[design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles).
How each one applies here:

| Principle | In this editor |
| :- | :- |
| **Purpose** | The piano roll is the product. It gets the space; panels around it stay compact. |
| **Agency** | Nothing locks people into a mode. Escape cancels a gesture, every edit is one REAPER Undo step, and switches and toggles show their state at a glance. |
| **Responsibility** | The editor writes only the clips on screen, says what it changed in the status line, and never runs code stored in MIDI. |
| **Familiarity** | Every button, toggle, switch and dropdown looks and behaves the same everywhere. Shortcuts follow REAPER and Ableton Live, and each control's tooltip names its shortcut. |
| **Flexibility** | Every state works from the smallest window (780 × 580) up. Text meets WCAG contrast. Mouse, keyboard and wheel all reach the same actions. |
| **Simplicity** | Short labels ("Draw", not "Draw [B]"), a clear hierarchy (one accent, one primary action per view), and secondary information in muted text. What does not fit is left out, never squeezed in. |
| **Craft** | One control height, one spacing scale, and no overlapping or misaligned controls. The layout audit checks this in every state. |
| **Delight** | Calm and practical: a dark, low-contrast chrome that lets the notes' colours lead. No decoration for its own sake. |

## Tokens

### Colour (`T.color`)

Named by role, never by look. Use the role that fits; add a token only for a
new role, and document it.

| Token | Role |
| :- | :- |
| `well` | Inputs, sliders, the piano roll and graphs: the darkest surface |
| `bg` | The window |
| `panel` | Sidebar, piano roll header rows, modulation panel |
| `raised`, `hover`, `press` | Buttons at rest, hovered and pressed |
| `line` | Borders and separators |
| `text` | Content and labels |
| `muted` | Secondary information: counts, units, status |
| `faint` | Section headings, hints, axis labels |
| `accent` (`_hover`, `_press`, `_text`) | The one accent: on-states, selection, the playhead, the primary action |
| `on_accent` | Text on an accent fill |
| Piano roll tokens (`key_*`, `row_*`, `*_line`, `range_*`, `note_*`, `view_*`, ...) | Canvas drawing only |

`T.clips` holds one colour per clip, in track order. These colours are data (which
clip a note belongs to), so they are the only saturated colours besides the accent.
`ui.alpha(color,a)` makes a translucent version of any token.

Contrast, checked by `tests/test_design.py`: `text` at least 7:1, `muted` and
`accent_text` at least 4.5:1, and `faint` at least 3:1, on every surface.

### Spacing (`T.space`)

`xs` 4, `sm` 8, `md` 16, `lg` 24. Every gap and padding is one of these. Items
in a row or column are `sm` apart; panels are `sm` apart; a heading gets `xs`
of room above it.

### Size (`T.size`)

| Token | px | For |
| :- | -: | :- |
| `control` | 24 | The height of every button, toggle, switch, dropdown, input, slider and list row |
| `button` | 56 | The minimum automatic button width |
| `icon` | 32 | Square-ish buttons with a symbol (÷2, ×2) |
| `field` | 64 | Short number inputs |
| `combo` | 80 | Dropdowns with short values |
| `wide` | 136 | Wider inputs and sliders in popups and panels |
| `sidebar` | 240 | The sidebar |
| `radius` | 6 | Panel corners |

Controls take a size **token** (`'field'`), `'fill'` for the rest of the row,
`{rest=w}` to fill the row but leave `w` for what follows, or nothing: an
automatic width that fits the label, at least `button`, rounded up to the 8 px
grid. Never pass a pixel number.

## Components

Create the theme once per ImGui context: `local ui=dofile(dir..'theme.lua').new(ImGui,ctx)`.
`ui.C`, `ui.space`, `ui.size` and `ui.clips` expose the tokens.

**Frame and audit.** `ui:push()` / `ui:pop()` wrap the window's style.
`ui:begin_frame(audit)` and `ui:end_frame()` run the layout audit.
`ui:anchor(name,x1,y1,x2,y2)` names a hand-drawn area (the ruler, a graph) so
tests can find it.

**Layout.**
- `ui:same_line()` puts the next item on the current row.
- `ui:right_align(width)` puts it at the row's right edge.
- `ui:center(width)` centres it horizontally in the panel, and `ui:middle(height)` centres a block vertically.
- `ui:gap(size)` adds vertical space; `ui:indent(level)` indents the next item by `lg`.
- `ui:separator()` draws a horizontal rule between sections; `ui:divider()` draws a vertical rule between toolbar groups.
- `ui:panel(id,w,h,fn,scroll)` is a bordered region laid out to fit, so it never scrolls unless `scroll` is set. `ui:column(fn)` stacks items beside the previous one.
- `ui:width(label,size)`, `ui:text_width(s)` and `ui:line_height()` measure things for alignment.

**Text.**
- `ui:text(s)`: content. `ui:muted(s)`: secondary information. `ui:faint(s)`: hints.
- `ui:colored(s,color)`: text in a clip's colour.
- `ui:wrapped(s)`: a paragraph. `ui:warning(s)`: something needs attention, wrapped, in the accent.
- `ui:heading(s,first)`: a section title in small caps.
- `ui:label(s,strong)`: text beside controls, centred on their height; `strong` for a panel title.
- `ui:key_hints(rows)` and `ui:key_hints_height(rows)`: a key and action cheat sheet.

**Controls.** Each takes a tooltip (name the shortcut in it) and a size.
- `ui:button(label,tip,size)`: an action. `ui:primary(label,tip,size)`: the one main action of a view (accent fill).
- `ui:toggle(label,on,tip,size)`: a button that stays on (tinted fill, outline, accent text).
- `ui:switch(label,value,tip)`: an on/off setting that is not an action.
- `ui:arrow(id,open,tip)`: disclosure for a collapsible panel.
- `ui:combo(id,preview,size,fn,tip)`: a dropdown that looks like a button. `fn` lists `ui:option(label,selected,color)` entries; `ui:option` also serves popup lists.
- `ui:list_row(id,selected,swatch,label,note,tip)`: a full-width row with a colour swatch and a right-aligned note.
- `ui:input_text(id,text,size,tip)` returns submitted, text and active. `ui:input_int(label,value,size,tip)`.
- `ui:slider_int(...)` and `ui:slider_double(...)` return changed, value and released (the edit is finished).
- `ui:region(id,w,h,flags)`: an area the caller draws and handles itself (the piano roll, a graph). `ui:handle_above(id,w,h)`: a resize handle in the gap above the cursor.
- `ui:tip(text)`: a tooltip for the last item, after a short hover.

Menus (`ImGui.BeginPopup`, `ImGui.MenuItem`), windows, input state (`ImGui.IsKeyPressed`,
`ImGui.IsItemHovered`, the mouse) and draw lists stay plain ImGui: they carry no
look of their own.

## Rules

1. **No raw widgets, styles or colours outside `theme.lua`.** UI files use `ui:`
   components and `ui.C` tokens. `tests/test_design.py` fails on any
   `ImGui.Button`, `Checkbox`, `Selectable`, `Slider*`, `Input*`, `Text*`,
   `BeginChild`, `Dummy`, `SetNextItemWidth`, `SetCursorPos*`, `SameLine` with an
   offset, `PushStyle*`, or colour literal in them.
2. **One control height.** Everything interactive is `size.control` high, so rows
   line up without adjustment.
3. **Sizes and gaps come from tokens.** Custom drawing inside a `ui:region` (the
   piano roll, graphs) uses pixel geometry, but its colours are still tokens.
4. **Fit, don't overflow.** A panel is laid out to fit its height. When something
   doesn't fit (the shortcut list in a short window), leave it out rather than
   scroll or overlap. The piano roll keeps a minimum height; other panels yield.
5. **Popups stay inside the window.** Anchor them to their button
   (`ImGui.SetNextWindowPos` with a pivot), as the Options menu does.
6. **Words.** Labels are short verbs or nouns in sentence case. Tooltips say what
   the control does and its shortcut. Status messages say what just happened.

## Adding something

- A new kind of control goes into `theme.lua` as a `ui:` function. It records
  itself with `track()` so the audit sees it, and it is listed in this document.
  `tests/test_design.py` fails if a component is missing here.
- A new colour is a new role token in `T.color`, never a literal where it is used.
- A new state or panel gets a case in `tests/reaper/layout_test.lua`.

## Enforcement

- `tests/test_design.py` (runs everywhere): the lint above, that every component
  is documented here, and the contrast targets.
- `tests/reaper/layout_test.lua` (runs in the headless REAPER): opens the editor
  in each state at the default and the smallest window size, with the layout audit
  on. It fails when a control overlaps another, leaves its panel, or is not
  `size.control` high.
- The audit also exports where every control is (`T.control(label)` in
  `tests/reaper/support.lua`), so UI tests click controls by name instead of by
  pixel.
