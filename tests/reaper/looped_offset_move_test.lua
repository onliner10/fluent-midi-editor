-- A clip that loops its source with a start offset shows its first pass from
-- the offset on. A note dragged before that pass would land in the part of
-- the source the clip never plays: it is refused like a note dragged before
-- the start of a plain clip, instead of vanishing.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item,take=T.midi_item(0,4,{{62,1.75,2.25},{65,3,3.5}},'Keys')
r.SetMediaItemInfo_Value(item,'D_POSITION',r.TimeMap2_QNToTime(0,2))
r.SetMediaItemInfo_Value(item,'D_LENGTH',r.TimeMap2_QNToTime(0,3))
r.SetMediaItemTakeInfo_Value(take,'D_STARTOFFS',r.TimeMap2_QNToTime(0,2))
r.UpdateItemInProject(item); r.Undo_OnStateChange('Test: loop with an offset')
local S,M=T.session(item)
T.eq(S.clips[1].native_repeats,true,'the clip loops its source')
local notes=M.copy(S.notes)
local moved
for _,n in ipairs(notes) do if n.pitch==62 then n.s=n.s-0.5; n.e=n.e-0.5; moved=n end end
T.ok(moved,'the note crossing the start is editable')
local ok,message=S:commit(notes,'Move notes')
T.eq(ok,false,'moving the note before the first pass')
T.eq(message,'A note starts before the beginning of clip Keys.','message')
T.eq(#T.notes(r.GetActiveTake(item)),2,'notes in the clip')
notes=M.copy(S.notes)
for _,n in ipairs(notes) do if n.pitch==62 then n.pitch=63 end end
T.ok(S:commit(notes,'Transpose'),'a note crossing the start keeps its start when transposed')
print('a note cannot be dragged out of a looped first pass')
