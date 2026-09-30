-- Ctrl + drag copies notes; a Ctrl+click without dragging only selects and
-- must not leave an invisible copy on top of the note.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local _,take=T.midi_item(0,8,{{60,0,4}},'Keys')
T.select(r.GetTrackMediaItem(r.GetTrack(0,0),0))
local note
return T.steps(T.concat(T.open_steps(),
  function() note=T.find(T.note_color(100)); T.ok(note,'note not drawn'); return true end,
  function() T.move(note.cx,note.cy); return true end,0.3,
  function() T.keydown('ctrl'); return true end,0.2,
  function() T.down(); return true end,0.3,
  function() T.up(); return true end,0.3,
  function() T.keyup('ctrl'); return true end,0.5,
  function()
    T.close_editor()
    local notes=T.notes(r.GetActiveTake(r.GetTrackMediaItem(r.GetTrack(0,0),0)))
    T.eq(#notes,1,'notes after Ctrl+click')
    print('Ctrl+click adds no copy')
    return true
  end))
