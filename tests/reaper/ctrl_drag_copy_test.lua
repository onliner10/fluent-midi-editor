-- Ctrl + drag copies the note to where it is dropped; the original stays.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
T.midi_item(0,8,{{60,0,1}},'Keys')
T.select(r.GetTrackMediaItem(r.GetTrack(0,0),0))
return T.steps(T.concat(T.open_steps(),
  function()
    local n=T.find(T.note_color(100)); T.ok(n,'note not drawn')
    local width=n[3]-n[1] -- one beat
    return {function() T.move(n.cx,n.cy); return true end,0.3,
      function() T.keydown('ctrl'); return true end,0.2,
      function() T.down(); return true end,0.3,
      function() T.move(n.cx+width,n.cy); return true end,0.3,
      function() T.move(n.cx+2*width,n.cy); return true end,0.3,
      function() T.up(); return true end,0.3,
      function() T.keyup('ctrl'); return true end,0.5}
  end,
  function()
    T.close_editor()
    local notes=T.notes(r.GetActiveTake(r.GetTrackMediaItem(r.GetTrack(0,0),0)))
    T.eq(#notes,2,'notes after Ctrl+drag')
    T.eq(string.format('%g-%g %g-%g',notes[1][2],notes[1][3],notes[2][2],notes[2][3]),'0-1 2-3','original and copy')
    print('Ctrl+drag copies')
    return true
  end))
