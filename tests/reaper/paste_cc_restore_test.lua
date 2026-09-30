-- Pasting a CC range into the middle of recorded CC changes only that range:
-- after it the controller goes back to the value the clip had there.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local source,stake=T.midi_item(0,8,{{60,0,1}},'Source')
r.MIDI_InsertCC(stake,false,false,0,0xB0,0,7,10); r.MIDI_Sort(stake)
local target,ttake=T.midi_item(0,8,{{48,0,1}},'Target')
r.MIDI_InsertCC(ttake,false,false,0,0xB0,0,7,50); r.MIDI_Sort(ttake)
r.Undo_OnStateChange('Test: recorded CC')
local S,M=T.session(source,target)
local fragment=T.copy_cc(S.clips[1],0,2)
S:set_active(2)
T.ok(S:commit(M.copy(S.notes),'Paste notes and modulation',3,{[2]=T.paste_cc(S.clips[2],fragment,1)}))
local take=r.GetActiveTake(S.clips[2].item)
T.eq(T.cc_at(take,0,7,2),10,'CC7 inside the pasted range')
T.eq(T.cc_at(take,0,7,4),50,'CC7 after the pasted range')
print('recorded CC returns after the pasted range')
