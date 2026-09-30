-- "+ CC" 74 on a member channel of an MPE recording. Either the editor
-- refuses the lane, or the lane it writes is editable and is the only CC74
-- on that channel; it must not play on top of the notes' own timbre.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item,take=T.midi_item(0,8,{},'Seaboard')
for i,ch in ipairs({1,2}) do
  local s=(i-1)*960*2
  r.MIDI_InsertCC(take,false,false,s,0xB0,ch,74,127)
  r.MIDI_InsertCC(take,false,false,s,0xE0,ch,0,64)
  r.MIDI_InsertNote(take,false,false,s,s+960*2,ch,60+i,100,true)
  r.MIDI_InsertCC(take,false,false,s+480,0xB0,ch,74,90)
end
r.MIDI_Sort(take); r.Undo_OnStateChange('Test: MPE')
local S=T.session(item)
local A=T.load('modulation'); local b=S.clips[1]
local _,bykey=T.write_lane(S,A.new_lane(1,74,b.edit_source_start,b.edit_source_end,.5))
local lane=bykey[A.key(1,74)]
T.ok(lane and not lane.stale,'the new CC74 lane is locked as changed outside the editor')
local at={}; local clash
for _,e in ipairs(T.ccs(r.GetActiveTake(S.clips[1].item))) do
  if e[2]==1 and e[3]==74 then
    if at[e[1]] and at[e[1]]~=e[4] then clash=string.format('tick %d has CC74 %d and %d',e[1],at[e[1]],e[4]) end
    at[e[1]]=e[4]
  end
end
T.ok(not clash,'two CC74 streams on channel 2: '..tostring(clash))
print('CC74 lane on an MPE channel')
