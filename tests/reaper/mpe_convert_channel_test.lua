-- Convert to MPE on a part that plays on MIDI channel 2 with a held bend:
-- the bend moves to the master channel, so every note still hears it.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item,take=T.midi_item(0,8,{},'Part')
for _,p in ipairs({60,64,67}) do r.MIDI_InsertNote(take,false,false,0,960*2,1,p,100,true) end
r.MIDI_InsertCC(take,false,false,0,0xE0,1,0x10,0x4E) -- channel 2 bend 10000
r.MIDI_Sort(take); r.Undo_OnStateChange('Test: part on channel 2')
local S,M=T.session(item)
local X=T.load('expression').new(M)
local notes=M.copy(S.notes)
local ok,channel=X.make_mpe(notes); T.ok(ok); T.eq(channel,1)
local raw=X.to_master(S.clips[1].source,channel); T.ok(raw,'controllers to move')
T.ok(S:commit(notes,'Convert clip to MPE',nil,{[1]={raw=raw}}))
local tk=r.GetActiveTake(item)
local _,_,ccs=r.MIDI_CountEvts(tk)
local master
for i=0,ccs-1 do local _,_,_,pos,chanmsg,chan,m1,m2=r.MIDI_GetCC(tk,i)
  if chanmsg==0xE0 and chan==0 then master=m1|(m2<<7) end
  if chanmsg==0xE0 and chan~=0 then T.eq(m1|(m2<<7),8192,'member channels stay neutral') end
end
T.eq(master,10000,'held bend on the master channel')
local _,count=r.MIDI_CountEvts(tk); local used={}
for i=0,count-1 do local _,_,_,_,_,chan=r.MIDI_GetNote(tk,i); T.ok(chan>=1 and not used[chan],'own member channel'); used[chan]=true end
T.ok(T.session(item).clips[1].source.mpe,'read again as MPE')
print('a part on channel 2 converts with its bend')
