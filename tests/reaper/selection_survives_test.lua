-- A change elsewhere in the project (here a track's volume) does not clear
-- the notes selected in the editor: select a note, move a fader, press
-- Delete, and the note is deleted.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local _,take=T.midi_item(0,8,{},'Keys')
r.MIDI_InsertNote(take,false,false,0,960,0,60,100,true)
r.MIDI_InsertNote(take,false,false,1920,2880,0,64,60,true)
r.MIDI_Sort(take); r.Undo_OnStateChange('Test: notes')
T.select(r.GetTrackMediaItem(r.GetTrack(0,0),0))
return T.steps(T.concat(T.open_steps(),
  function()
    local a=T.find(T.note_color(100)); T.ok(a,'notes not drawn')
    return T.click_steps(a.cx,a.cy)
  end,
  function() r.SetMediaTrackInfo_Value(r.GetTrack(0,0),'D_VOL',0.5); r.Undo_OnStateChange('Test: fader'); return true end,
  0.8,
  function() T.keys('Delete'); return true end,0.5,
  function()
    T.close_editor()
    local count=#T.notes(r.GetActiveTake(r.GetTrackMediaItem(r.GetTrack(0,0),0)))
    T.eq(count,1,'notes after selecting one, moving a fader and pressing Delete')
    print('selection survives unrelated project changes')
    return true
  end))
