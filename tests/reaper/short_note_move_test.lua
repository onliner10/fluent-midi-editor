-- Dragging the middle of a 1/16 note in an 8-bar clip, shown whole as it
-- opens, moves it. The resize zones at its edges must leave room to grab
-- the note itself.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
T.midi_item(0,32,{{60,1,1.25}},'Keys')
T.select(r.GetTrackMediaItem(r.GetTrack(0,0),0))
return T.steps(T.concat(T.open_steps(),
  function()
    local note=T.find(T.note_color(100)); T.ok(note,'note not drawn')
    return T.drag_steps(note.cx,note.cy,note.cx+120,note.cy)
  end,
  function()
    T.close_editor()
    local n=T.notes(r.GetActiveTake(r.GetTrackMediaItem(r.GetTrack(0,0),0)))[1]
    T.eq(string.format('%.3f',n[3]-n[2]),'0.250','length after dragging the middle of the note')
    T.ok(n[2]>1.5,'the note did not move; it starts at '..n[2])
    print('short notes can be moved')
    return true
  end))
