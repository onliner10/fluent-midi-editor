-- F folds the piano roll to the used pitches. It changes rows only; the
-- horizontal zoom and scroll stay where the user put them.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
T.midi_item(0,16,{{60,1,2},{67,2,3}},'Keys')
T.select(r.GetTrackMediaItem(r.GetTrack(0,0),0))
local zoomed
local function width() local n=T.find(T.note_color(100)); T.ok(n,'note not drawn'); return n[3]-n[1] end
return T.steps(T.concat(T.open_steps(),
  function() local n=T.find(T.note_color(100)); return T.click_steps(n.cx,n.cy+60) end,
  function() T.keydown('ctrl'); return true end,0.2,
  function() os.execute('DISPLAY=:99 xdotool click --repeat 3 --delay 120 4'); return true end,0.5,
  function() T.keyup('ctrl'); return true end,0.5,
  function() zoomed=width(); return true end,
  function() T.keys('f'); return true end,0.6,
  function()
    T.close_editor()
    local folded=width()
    T.eq(folded,zoomed,'note width in pixels after F (zoomed in first)')
    print('F keeps the zoom')
    return true
  end))
