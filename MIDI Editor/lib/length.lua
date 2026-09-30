-- Item length and playback-loop range, without deleting or stretching source MIDI.
local L={}
function L.parse(text)
  text=tostring(text):match('^%s*(.-)%s*$'):gsub(',','.')
  if not text:match('^%d*%.?%d+$') then return nil,'Enter a number of bars, e.g. 4 or 0.5.' end
  local value=tonumber(text)
  if not value or value<=0 or value>4096 then return nil,'Length must be greater than 0 and at most 4096 bars.' end
  return value
end
function L.format(value) return string.format('%.8f',value):gsub('0+$',''):gsub('%.$',''):gsub('%.',',') end
local function bar_position(r,project,qn)
  local measure,a,b=r.TimeMap_QNToMeasures(project,qn)
  -- QNToMeasures numbers measures from 1; GetMeasureInfo indexes from 0.
  return measure-1+(qn-a)/(b-a)
end
function L.bars(r,b)
  local start=r.TimeMap2_timeToQN(b.project,b.position)
  local ending=r.TimeMap2_timeToQN(b.project,b.position+b.item_length)
  return bar_position(r,b.project,ending)-bar_position(r,b.project,start)
end
function L.span_bars(r,project,start,ending)
  return bar_position(r,project,ending)-bar_position(r,project,start)
end
function L.phrase_bars(r,b)
  return L.span_bars(r,b.project,b.origin,b.origin+b.length)
end
function L.end_qn(r,b,bars)
  local start=r.TimeMap2_timeToQN(b.project,b.position)
  local target=bar_position(r,b.project,start)+bars
  local measure=math.floor(target+1e-9)
  local _,a,z=r.TimeMap_GetMeasureInfo(b.project,measure)
  return a+(target-measure)*(z-a)
end
-- phrase: the phrase module, which rewrites the source when it must grow.
-- duplicate: the part that grows gets copies of the current clip, not silence.
function L.resize(r,b,bars,match_loop,group_transaction,phrase,duplicate)
  if not b or not b:valid() then return false,'The project or clip changed. Select the clip again.' end
  if type(bars)~='number' or bars~=bars or bars<=0 or bars>4096 then return false,'Enter a length above 0 and up to 4096 bars.' end
  if r.GetPlayStateEx(b.project)&4~=0 then return false,'Stop recording before changing the length.' end
  if r.GetMediaItemInfo_Value(b.item,'C_LOCK')&1~=0 then return false,'The clip is locked.' end
  if b:changed() then return false,'The clip changed in REAPER. Enter the length again.' end
  local ending=L.end_qn(r,b,bars)
  local start=r.TimeMap2_timeToQN(b.project,b.position)
  if b.to_ppq(ending-b.origin)-b.to_ppq(start-b.origin)<1 then return false,'The clip must be at least one MIDI tick long.' end
  local seconds=r.TimeMap2_QNToTime(b.project,ending)-b.position
  local a,z=r.GetSet_LoopTimeRange2(b.project,false,true,0,0,false)
  if math.abs(seconds-b.item_length)<1e-8 and
    (not match_loop or math.abs(a-b.position)<1e-8 and math.abs(z-b.position-seconds)<1e-8) then return true end
  -- A clip that plays one pass of its looped source keeps Loop source on: the
  -- source grows with the clip, and a trim keeps its tail hidden in the source.
  -- Repeated sources need materializing first.
  if b.looped and not b.single then
    return false,'The clip loops its MIDI source. Glue it in REAPER first to change its length here.'
  end
  local old_end=r.TimeMap2_timeToQN(b.project,b.position+b.item_length)
  local raw
  if duplicate and ending>old_end+1e-9 then
    raw=phrase.duplicate(b.source,b.to_ppq(start-b.origin),b.to_ppq(old_end-b.origin),b.to_ppq(ending-b.origin))
  elseif b.looped and b.to_ppq(ending-b.origin)>b.source.end_ppq then
    raw=phrase.lengthen(b.source,b.to_ppq(ending-b.origin))
  end
  local got,chunk=r.GetItemStateChunk(b.item,'',false)
  if not got then return false,'Could not back up the clip.' end
  local ta,tz=r.GetSet_LoopTimeRange2(b.project,false,false,0,0,false)
  if not group_transaction then r.Undo_BeginBlock2(b.project); r.PreventUIRefresh(1) end
  local ok,err=xpcall(function()
    if raw then assert(r.MIDI_SetAllEvts(b.take,raw),'Could not write MIDI'); r.MIDI_Sort(b.take) end
    assert(r.SetMediaItemInfo_Value(b.item,'D_LENGTH',seconds),'Could not change the clip length')
    r.UpdateItemInProject(b.item)
    if match_loop then r.GetSet_LoopTimeRange2(b.project,true,true,b.position,b.position+seconds,false) end
  end,debug.traceback)
  local restored=true
  if not ok then
    restored=r.SetItemStateChunk(b.item,chunk,false)
    r.GetSet_LoopTimeRange2(b.project,true,true,a,z,false)
    r.GetSet_LoopTimeRange2(b.project,true,false,ta,tz,false)
  end
  if not group_transaction then
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock2(b.project,'Fluent MIDI Editor: Change clip length'..(match_loop and ' and loop' or ''),-1)
  end
  r.UpdateArrange(); b.take=r.GetActiveTake(b.item); b:read()
  if not ok then return false,(restored and 'Clip restored. ' or 'Use Undo. ')..tostring(err) end
  return true
end
return L
