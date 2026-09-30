-- The editor opens with all notes of the clip in view. Notes four octaves
-- apart fit when rows get as short as Alt + wheel allows (10 px).
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local _,take=T.midi_item(0,8,{},'Keys')
r.MIDI_InsertNote(take,false,false,0,960,0,40,100,true)
r.MIDI_InsertNote(take,false,false,960,1920,0,88,60,true)
r.MIDI_Sort(take); r.Undo_OnStateChange('Test: notes')
T.select(r.GetTrackMediaItem(r.GetTrack(0,0),0))
return T.steps(T.concat(T.open_steps(),
  function()
    T.close_editor()
    local screen=T.screen()
    T.ok(T.find(T.note_color(100),screen),'the low note (E1) is not in view')
    T.ok(T.find(T.note_color(60),screen),'the high note (E6) is not in view')
    print('opening shows all notes')
    return true
  end))
