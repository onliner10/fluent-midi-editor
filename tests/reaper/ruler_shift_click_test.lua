-- Shift + click on the ruler scrubs, as in Ableton: playback starts from that
-- point. It selects nothing, so Delete right after it deletes nothing.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
T.midi_item(0,8,{{60,1,2}},'Keys')
T.select(r.GetTrackMediaItem(r.GetTrack(0,0),0))
local cursor
return T.steps(T.concat(T.open_steps(),
  function()
    local n=T.find(T.note_color(100)); T.ok(n,'note not drawn')
    return T.concat({function() T.keydown('shift'); return true end,0.2},
      T.click_steps(n.cx,T.ruler_y()),{function() T.keyup('shift'); return true end,0.3})
  end,
  function()
    local playing=r.GetPlayState()&1~=0
    cursor=r.TimeMap2_timeToQN(0,r.GetCursorPosition())
    r.OnStopButton()
    T.ok(playing,'Shift+click on the ruler did not start playback')
    T.ok(cursor>1 and cursor<2,'playback should start at the click (inside the note, beats 1-2), edit cursor at '..cursor)
    T.keys('Delete'); return true
  end,0.5,
  function()
    T.close_editor()
    T.eq(#T.notes(r.GetActiveTake(r.GetTrackMediaItem(r.GetTrack(0,0),0))),1,'notes after Shift+click on the ruler and Delete')
    print('Shift+click on the ruler plays from there')
    return true
  end))
