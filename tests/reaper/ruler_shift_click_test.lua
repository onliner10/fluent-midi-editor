-- Shift + drag on the ruler selects a time range. A Shift+click without
-- dragging selects nothing (like a plain click in the grid), so Delete right
-- after it deletes nothing.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
T.midi_item(0,8,{{60,1,2}},'Keys')
T.select(r.GetTrackMediaItem(r.GetTrack(0,0),0))
return T.steps(T.concat(T.open_steps(),
  function()
    local n=T.find(T.note_color(100)); T.ok(n,'note not drawn')
    return T.concat({function() T.keydown('shift'); return true end,0.2},
      T.click_steps(n.cx,T.ruler_y()),{function() T.keyup('shift'); return true end,0.3})
  end,
  function() T.keys('Delete'); return true end,0.5,
  function()
    T.close_editor()
    T.eq(#T.notes(r.GetActiveTake(r.GetTrackMediaItem(r.GetTrack(0,0),0))),1,'notes after Shift+click on the ruler and Delete')
    print('Shift+click on the ruler selects nothing')
    return true
  end))
