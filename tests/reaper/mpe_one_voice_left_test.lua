-- An MPE recording stays MPE after the editor deletes all voices but one:
-- moving the remaining note still takes its slide along.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item,take=T.midi_item(0,8,{},'Seaboard')
r.MIDI_InsertCC(take,false,false,0,0xE0,1,0,64)
r.MIDI_InsertNote(take,false,false,0,960,1,60,100,true)
r.MIDI_InsertCC(take,false,false,480,0xE0,1,0,96)       -- C4 slides up
r.MIDI_InsertCC(take,false,false,960,0xE0,2,0,64)
r.MIDI_InsertNote(take,false,false,960,1920,2,64,100,true)
r.MIDI_InsertCC(take,false,false,1440,0xE0,2,0,32)      -- E4 slides down
r.MIDI_Sort(take); r.Undo_OnStateChange('Test: MPE')
local S,M=T.session(item)
local notes=M.copy(S.notes)
for i=#notes,1,-1 do if notes[i].pitch==60 then table.remove(notes,i) end end
T.ok(S:commit(notes,'Delete note'))
notes=M.copy(S.notes); notes[1].s,notes[1].e=4,5
T.ok(S:commit(notes,'Move note'))
local bend
local tk=r.GetActiveTake(S.clips[1].item)
local _,_,count=r.MIDI_CountEvts(tk)
for i=0,count-1 do local _,_,_,pos,status,ch,_,msb=r.MIDI_GetCC(tk,i)
  if status==0xE0 and ch==2 and msb==32 then bend=pos/960 end end
T.eq(bend,4.5,'beat of E4 slide after moving E4 to beat 4')
print('one MPE voice keeps its expression')
