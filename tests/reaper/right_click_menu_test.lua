-- Right-clicking a note opens the note menu for that note: select note A,
-- right-click note B, choose Delete, and B is deleted, not A.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local _,take=T.midi_item(0,8,{},'Keys')
r.MIDI_InsertNote(take,false,false,0,960,0,60,100,true)  -- A
r.MIDI_InsertNote(take,false,false,1920,2880,0,64,60,true) -- B
r.MIDI_Sort(take); r.Undo_OnStateChange('Test: notes')
T.select(r.GetTrackMediaItem(r.GetTrack(0,0),0))
return T.steps(T.concat(T.open_steps(),
  function()
    local screen=T.screen()
    local a,b=T.find(T.note_color(100),screen),T.find(T.note_color(60),screen)
    T.ok(a and b,'notes not drawn')
    -- The menu opens at the pointer; Delete is its fourth item.
    return T.concat(T.click_steps(a.cx,a.cy),T.click_steps(b.cx,b.cy,3),T.click_steps(b.cx+28,b.cy+78))
  end,
  function()
    T.close_editor()
    local left={}
    for _,n in ipairs(T.notes(r.GetActiveTake(r.GetTrackMediaItem(r.GetTrack(0,0),0)))) do left[#left+1]=n[1] end
    T.eq(table.concat(left,','),'60','notes left after right-clicking note 64 and choosing Delete')
    print('the note menu acts on the clicked note')
    return true
  end))
