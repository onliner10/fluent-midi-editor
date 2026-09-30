-- X (show all clips) fits the notes to the piano roll the window really has,
-- the same view the editor opens with.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local _,take=T.midi_item(0,8,{},'Keys')
r.MIDI_InsertNote(take,false,false,0,960,0,60,100,true)
r.MIDI_InsertNote(take,false,false,960,1920,0,72,60,true)
r.MIDI_Sort(take); r.Undo_OnStateChange('Test: notes')
T.select(r.GetTrackMediaItem(r.GetTrack(0,0),0))
local low,high
return T.steps(T.concat(T.open_steps(),
  function()
    local screen=T.screen()
    low,high=T.find(T.note_color(100),screen),T.find(T.note_color(60),screen)
    T.ok(low and high,'notes not drawn when opening')
    return T.click_steps(low.cx+200,low.cy-2,1) -- focus the grid on an empty cell
  end,
  function() T.keys('Escape','x'); return true end,0.6,
  function()
    T.close_editor()
    local screen=T.screen()
    local l,h=T.find(T.note_color(100),screen),T.find(T.note_color(60),screen)
    T.ok(l and h,'X hides a note ('..(l and 'high' or 'low')..' pitch is off-screen)')
    T.eq(l[2]..','..h[2],low[2]..','..high[2],'note rows after X compared with opening')
    print('X shows the opening view')
    return true
  end))
