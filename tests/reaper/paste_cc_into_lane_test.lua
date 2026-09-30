-- Ctrl+C / Ctrl+V of recorded CC into a clip whose CC is a modulation lane.
-- The pasted range joins the lane; the lane keeps its name and stays editable.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local A=T.load('modulation')
local recorded,rtake=T.midi_item(0,8,{{60,0,1}},'Recorded')
r.MIDI_InsertCC(rtake,false,false,0,0xB0,0,1,10)
r.MIDI_InsertCC(rtake,false,false,960,0xB0,0,1,90)
r.MIDI_Sort(rtake); r.Undo_OnStateChange('Test: recorded CC')
local target=T.midi_item(0,8,{{48,0,1}},'Target')
local S,M=T.session(recorded,target)
S:set_active(2)
local lane=A.new_lane(0,1,0,8,.3,'Cutoff')
T.write_lane(S,lane)
local fragment=T.copy_cc(S.clips[1],0,2)
S:set_active(2)
T.ok(S:commit(M.copy(S.notes),'Paste notes and modulation',2,{[2]=T.paste_cc(S.clips[2],fragment,0)}))
local _,bykey=T.lanes(S)
local pasted=bykey[A.key(0,1)]
T.ok(pasted.managed,'the lane is no longer a modulation lane after the paste')
T.eq(pasted.label,'Cutoff','lane name')
T.ok(not pasted.stale,'the lane is locked as changed outside the editor')
print('pasted CC joins the lane')
