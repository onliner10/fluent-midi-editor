-- Shift+Left shortens a note by a grid step. On a note one step long it must
-- not leave a note one tick long, which is invisible in the piano roll.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
T.midi_item(0,8,{{60,1,1.25}},'Keys')
T.select(r.GetTrackMediaItem(r.GetTrack(0,0),0))
return T.steps(T.concat(T.open_steps(),
  function() local n=T.find(T.note_color(100)); T.ok(n,'note not drawn'); return T.click_steps(n.cx,n.cy) end,
  function() T.keydown('shift'); return true end,0.3,
  function() T.keys('Left'); return true end,0.3,
  function() T.keyup('shift'); return true end,0.5,
  function()
    T.close_editor()
    local n=T.notes(r.GetActiveTake(r.GetTrackMediaItem(r.GetTrack(0,0),0)))[1]
    local ticks=(n[3]-n[2])*960
    T.ok(ticks>=60,string.format('the 1/16 note is %g ticks long after Shift+Left',ticks))
    print('Shift+Left keeps a visible note')
    return true
  end))
