-- An ordinary mono line on MIDI channel 2 with pitch bend is not an MPE
-- recording (guide: MPE is recognised "when several channels each play one
-- note at a time"). A note added to it stays on the channel the user chose,
-- so a synth listening on channel 2 still plays it.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item,take=T.midi_item(0,8,{},'Lead')
r.MIDI_InsertNote(take,false,false,0,960*4,1,60,100,true)
r.MIDI_InsertCC(take,false,false,480,0xE0,1,0,80) -- bend up on channel 2
r.MIDI_Sort(take)
r.Undo_OnStateChange('Test: bend')
local M=T.load('model')
local S=T.load('session').new(r,M,T.load('backend'),T.load('repetition'),T.load('phrase'))
S:attach({item})
local notes=M.copy(S.notes)
notes[#notes+1]={s=1,e=2,pitch=64,vel=100,channel=1,selected=true,muted=false,take_index=1}
T.ok(S:commit(notes,'Add note'))
take=r.GetActiveTake(S.clips[1].item)
local _,count=r.MIDI_CountEvts(take)
for i=0,count-1 do
  local _,_,_,_,_,channel,pitch=r.MIDI_GetNote(take,i)
  if pitch==64 then T.eq(channel+1,2,'MIDI channel of the added note') end
end
print('mono channel with bend keeps its channel')
