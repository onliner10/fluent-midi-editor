-- The Phrase length field and ÷2 in the editor: typing a length and pressing
-- Enter, or clicking ÷2, changes the clip and reports the new length (the
-- status once called the length instead of the label helper and failed).
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
T.midi_item(0,8,{{60,0,1},{64,4,5}},'Keys')
T.select(r.GetTrackMediaItem(r.GetTrack(0,0),0))
local function clip_length() return r.TimeMap2_timeToQN(0,r.GetMediaItemInfo_Value(r.GetTrackMediaItem(r.GetTrack(0,0),0),'D_LENGTH')) end
return T.steps(T.concat(T.open_steps(),
  function() local c=T.control('÷2##length_half'); return T.click_steps(c.cx,c.cy) end,0.5,
  function() T.eq(clip_length(),4,'clip length after ÷2'); return true end,
  function() local c=T.control('##clip_length'); return T.click_steps(c.cx,c.cy) end,0.3,
  function() T.keys('ctrl+a','3','comma','5','Return'); return true end,0.5,
  function() T.eq(clip_length(),14,'clip length after typing 3,5'); return true end,
  function() local c=T.control('##clip_length'); return T.click_steps(c.cx,c.cy) end,0.3,
  function() T.keys('ctrl+a','x','Return'); return true end,0.5,
  function()
    T.eq(clip_length(),14,'clip length after typing a letter')
    T.eq(T.audit_problems(),'','layout problems')
    T.close_editor()
    print('typing a length or clicking ÷2 changes the clip')
    return true
  end))
