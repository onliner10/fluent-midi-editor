-- Clicking ÷2 in Phrase length shortens the clip and reports the new length
-- in the status line (the status once called the length instead of the
-- label helper and raised an error).
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
T.midi_item(0,8,{{60,0,1},{64,4,5}},'Keys')
T.select(r.GetTrackMediaItem(r.GetTrack(0,0),0))
return T.steps(T.concat(T.open_steps(),
  function() local c=T.control('÷2##length_half'); return T.click_steps(c.cx,c.cy) end,0.5,
  function()
    T.close_editor()
    local it=r.GetTrackMediaItem(r.GetTrack(0,0),0)
    T.eq(r.TimeMap2_timeToQN(0,r.GetMediaItemInfo_Value(it,'D_LENGTH')),4,'clip length after ÷2')
    print('clicking ÷2 halves the clip')
    return true
  end))
