-- Real REAPER takes: an MPE recording keeps each note's expression when the
-- editor moves, copies or deletes notes, and REAPER plays back what we wrote.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item,take=T.midi_item(0,8,{},'MPE')
local function ppq(qn) return r.MIDI_GetPPQPosFromProjQN(take,qn) end
local function pb(ch,v) return string.char(0xE0|ch,v&127,v>>7) end
local list={
  {0,pb(1,8192)},{0,string.char(0xD1,0)},{0,string.char(0x90|1,60,100)},
  {ppq(.5),pb(1,8192+683)},{ppq(.75),string.char(0xD1,90)},{ppq(.9375),string.char(0x81,60,0)},
  {ppq(1),pb(2,8192)},{ppq(1),string.char(0x90|2,64,100)},{ppq(1.25),pb(2,8192-400)},
  {ppq(1.875),string.char(0x82,64,0)},{ppq(8),string.char(0xB0,123,0)}}
local parts,last={},0
for _,e in ipairs(list) do parts[#parts+1]=string.pack('i4Bs4',math.floor(e[1]+.5)-last,0,e[2]); last=math.floor(e[1]+.5) end
T.ok(r.MIDI_SetAllEvts(take,table.concat(parts)),'write MPE take')
r.MIDI_Sort(take); r.Undo_OnStateChange('Test: MPE take')

-- What REAPER stores: {qn, channel, kind, value} of pitch bend and pressure.
local function expression()
  local tk=r.GetActiveTake(r.GetTrackMediaItem(r.GetTrack(0,0),0))
  local out={}
  local _,_,ccs=r.MIDI_CountEvts(tk)
  for i=0,ccs-1 do
    local _,_,_,pos,chanmsg,chan,m1,m2=r.MIDI_GetCC(tk,i)
    local value=chanmsg==0xE0 and (m1|(m2<<7)) or m1
    out[#out+1]={r.MIDI_GetProjQNFromPPQPos(tk,pos),chan,chanmsg,value}
  end
  return out,tk
end
local function at(list,qn,chan,kind)
  for _,e in ipairs(list) do if math.abs(e[1]-qn)<1e-6 and e[2]==chan and e[3]==kind then return e[4] end end
end

local M=T.load('model')
local S=T.load('session').new(r,M,T.load('backend'),T.load('repetition'),T.load('phrase'))
T.select(item); S:attach(S:selected_items())
T.eq(#S.notes,2,'notes'); T.ok(S.clips[1].source.mpe,'recognised as MPE')

-- Move C3 two beats later.
local notes=M.copy(S.notes)
for _,n in ipairs(notes) do if n.pitch==60 then n.s=n.s+2; n.e=n.e+2 end end
T.ok(S:commit(notes,'Move notes'))
local ex=expression()
T.eq(at(ex,2.5,1,0xE0),8192+683,'slide moved to beat 2.5')
T.eq(at(ex,2.75,1,0xD0),90,'pressure moved')
T.eq(at(ex,2,1,0xE0),8192,'starting bend moved')
T.eq(at(ex,.5,1,0xE0),nil,'no bend left at the old spot')
T.eq(at(ex,1.25,2,0xE0),8192-400,'E3 untouched')

-- Copy E3 on top of itself: the copy gets another channel and the same bend.
notes=M.copy(S.notes)
for _,n in ipairs(M.copy(notes)) do if n.pitch==64 then n.id=nil; n.s=n.s+.25; n.e=n.e+.25; notes[#notes+1]=n end end
T.ok(S:commit(notes,'Copy note'))
ex=expression()
local copies=0
for _,e in ipairs(ex) do if e[3]==0xE0 and math.abs(e[1]-1.5)<1e-6 and e[4]==8192-400 and e[2]~=2 then copies=copies+1 end end
T.eq(copies,1,'copy bends on its own channel')
T.eq(at(ex,1.25,2,0xE0),8192-400,'original keeps its bend')

-- Delete C3: its expression goes with it.
notes=M.copy(S.notes)
for i=#notes,1,-1 do if notes[i].pitch==60 then table.remove(notes,i) end end
T.ok(S:commit(notes,'Delete note'))
ex=expression()
for _,e in ipairs(ex) do T.ok(e[2]~=1,'no channel 2 expression after deleting C3') end

-- One Undo restores the previous state.
r.Undo_DoUndo2(0)
T.eq(at(expression(),2.5,1,0xE0),8192+683,'undo restores C3 and its slide')
print('MPE expression follows moved, copied and deleted notes')
