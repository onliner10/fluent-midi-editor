-- A clip that loops its source shows its later passes as "Loop pass" strips.
-- Clicking one writes the loop out: the whole clip becomes editable.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item,take=T.midi_item(0,4,{{60,0,1}},'Keys')
r.SetMediaItemInfo_Value(item,'D_LENGTH',r.TimeMap2_QNToTime(0,8))
r.Undo_OnStateChange('Test: loop source twice')
T.select(item)
return T.steps(T.concat(T.open_steps(),
  function()
    local strip=T.control('loop pass 1')
    return T.click_steps(strip.cx,strip.cy)
  end,
  function()
    T.eq(T.audit_problems(),'','layout problems')
    local it=r.GetTrackMediaItem(r.GetTrack(0,0),0)
    T.close_editor()
    T.eq(r.GetMediaItemInfo_Value(it,'B_LOOPSRC'),0,'Loop source after unrolling')
    T.eq(#T.notes(r.GetActiveTake(it)),2,'notes after unrolling')
    T.eq(r.TimeMap2_timeToQN(0,r.GetMediaItemInfo_Value(it,'D_LENGTH')),8,'clip length')
    print('clicking a loop pass unrolls the loop')
    return true
  end))
