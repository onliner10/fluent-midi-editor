-- Everything a note owns travels with it: MPE expression, polyphonic
-- aftertouch and REAPER notation. Plain channel controllers stay put.
local root=...
local M=dofile(root..'/MIDI Editor/lib/model.lua')
local A=dofile(root..'/MIDI Editor/lib/modulation.lua')
local count=0
local function eq(a,b,label) count=count+1; assert(a==b,(label or '')..': '..tostring(a)..' ~= '..tostring(b)) end
local function ok(v,label) count=count+1; assert(v,label) end
local Q=960
local from,to=function(t) return t/Q end,function(q) return q*Q end
-- Events given with absolute positions; packed as REAPER's delta stream.
local function stream(list)
  local parts,last={},0
  for _,e in ipairs(list) do
    parts[#parts+1]=string.pack('i4Bs4',e[1]-last,e[3] or 0,e[2]); last=e[1]
  end
  return table.concat(parts)
end
local function on(ch,p,v) return string.char(0x90|ch,p,v or 100) end
local function off(ch,p) return string.char(0x80|ch,p,0) end
local function pb(ch,v) return string.char(0xE0|ch,v&127,v>>7) end
local function at(ch,v) return string.char(0xD0|ch,v) end
local function tb(ch,v) return string.char(0xB0|ch,74,v) end
local END=string.char(0xB0,123,0)
local function decode(raw) return M.decode(raw,from) end
local function encode(source,notes,ending) return M.encode(source,notes,to,ending) end
local function find(source,pitch) for _,n in ipairs(source.notes) do if n.pitch==pitch then return n end end end
-- Controller state of a channel right before the note-on at pos, as a synth hears it.
local function state_at(source,channel,pos)
  local state={}
  for _,e in ipairs(source.events) do
    if e.pos>pos then break end
    local d,c,v=M.expression(e.msg)
    if d and c==channel then state[d]=v end
    if e.note_id and e.is_on and e.pos==pos and (e.msg:byte(1)&15)==channel then break end
  end
  return state
end
-- Expression of a note as {dt, message without channel}, to compare across moves.
local function shape(n)
  local out={}
  for _,x in ipairs(n.expr or {}) do
    local d,_,v=M.expression(x.msg)
    out[#out+1]=string.format('%.6f:%s=%s',x.dt,d or x.msg:sub(1,6),v or '')
  end
  return table.concat(out,' ')
end
local function events_of(source,channel,a,z)
  local out={}
  for _,e in ipairs(source.events) do
    local d,c=M.expression(e.msg)
    if d and c==channel and e.pos>=a and e.pos<z then out[#out+1]=e end
  end
  return out
end

-- An MPE take: C3 on channel 2 slides up two semitones, E3 on channel 3
-- presses harder and opens the timbre. Each note is set up just before its
-- note-on, as MPE controllers send it.
local center,up2=8192,8192+683
local raw=stream({
  {0,pb(1,center)},{0,at(1,0)},{0,tb(1,64)},{0,on(1,60)},
  {240,pb(1,8192+300)},{480,pb(1,up2)},{600,at(1,90)},{900,off(1,60)},
  {960,pb(2,center)},{960,at(2,10)},{960,tb(2,40)},{960,on(2,64)},
  {1200,at(2,100)},{1440,tb(2,110)},{1800,off(2,64)},
  {3840,END}})
local mpe=decode(raw)
eq(mpe.mpe,true,'several expressive single-note channels are MPE')
eq(#mpe.notes,2)
local c3,e3=find(mpe,60),find(mpe,64)
eq(#c3.expr,6,'C3 owns its setup and its slide'); eq(#e3.expr,5,'E3 owns its setup and expression')
eq(c3.initial.pb,center); eq(e3.initial.tb,40)
eq(encode(mpe,M.copy(mpe.notes)),raw,'untouched MPE take stays byte exact')
-- Opening the take in the modulation panel does not list per-note timbre.
eq(#A.read(mpe,from),0,'owned CC74 is not a modulation lane')

-- 1. Moving a note moves its expression.
local notes=M.copy(mpe.notes); notes[1].selected=true; notes[2].selected=false
M.move(notes,2,0,0)
local moved=decode(encode(mpe,notes,to(4)))
local c3m=find(moved,60)
eq(c3m.on.pos,1920,'note moved'); eq(shape(c3m),shape(c3),'slide moved with the note')
eq(#events_of(moved,1,0,1920),0,'nothing is left behind on the old spot')
eq(state_at(moved,1,1920).pb,center,'moved note starts in tune')
eq(shape(find(moved,64)),shape(e3),'the other note is untouched')

-- 2. Transposing keeps the bend (it is relative) and the channel.
notes=M.copy(mpe.notes); notes[1].pitch=67
local transposed=decode(encode(mpe,notes))
eq(shape(find(transposed,67)),shape(c3),'transpose keeps expression')

-- 3. A copy on top of its original gets a free channel and its own expression.
notes=M.copy(mpe.notes)
local copy=M.copy(notes[1]); copy.id=nil; copy.s=copy.s+.5; copy.e=copy.e+.5; notes[#notes+1]=copy
local copied=decode(encode(mpe,notes,to(4)))
eq(#copied.notes,3)
local channels={}
for _,n in ipairs(copied.notes) do if n.pitch==60 then channels[#channels+1]=n.channel end end
ok(channels[1]~=channels[2],'overlapping copy uses another channel')
for _,n in ipairs(copied.notes) do if n.pitch==60 then eq(shape(n),shape(c3),'copy and original both slide') end end
eq(shape(find(copied,64)),shape(e3),'copy does not disturb other notes')
eq(copied.mpe,true)

-- 4. Deleting a note deletes its expression, not the neighbour's.
notes=M.copy(mpe.notes); table.remove(notes,1)
-- One voice is left; the editor remembers the clip was MPE when it wrote it.
local deleted=M.decode(encode(mpe,notes),from,true)
eq(#events_of(deleted,1,0,3840),0,'deleted note leaves no bend behind')
eq(shape(find(deleted,64)),shape(e3))

-- 5. Resizing one edge leaves the expression where it is.
notes=M.copy(mpe.notes); notes[1].e=notes[1].e-.5
local resized=decode(encode(mpe,notes))
local c3r=find(resized,60)
eq(c3r.off.pos,420); eq(#events_of(resized,1,0,3840),6,'expression stays after shortening')
eq(events_of(resized,1,0,3840)[5].pos,480,'bend stays at its time')

-- 6. A note that relied on the channel state left by an earlier note keeps
-- that state when the earlier note moves away.
raw=stream({
  {0,pb(1,center)},{0,on(1,60)},{480,pb(1,up2)},{900,off(1,60)},
  {960,pb(2,center)},{960,on(1,62)},{960,on(2,64)},{1200,pb(2,center+100)},
  {1400,off(1,62)},{1800,off(2,64)},{3840,END}})
local relied=decode(raw)
eq(relied.mpe,true)
eq(find(relied,62).initial.pb,up2,'D3 starts where C3 left the bend')
notes=M.copy(relied.notes)
for _,n in ipairs(notes) do if n.pitch==60 then n.s=n.s+2; n.e=n.e+2 end end
local after=decode(encode(relied,notes,to(4)))
eq(state_at(after,1,960).pb,up2,'D3 still starts where it did')
local moved_c3=find(after,60)
eq(state_at(after,moved_c3.channel,moved_c3.on.pos).pb,center,'moved C3 starts in tune')
eq(shape(moved_c3),shape(find(relied,60)))

-- 7. Moving a note next to another on its channel must not bend that one.
notes=M.copy(relied.notes)
for _,n in ipairs(notes) do if n.pitch==62 then n.s=n.s-.25; n.e=n.e-.25 end end
local close=decode(encode(relied,notes))
local d3=find(close,62)
eq(state_at(close,d3.channel,d3.on.pos).pb,up2,'moved D3 keeps its start state')
eq(state_at(close,1,0).pb,center,'C3 unchanged')

-- 8. A new note drawn over a sounding MPE note gets its own channel and starts neutral.
notes=M.copy(mpe.notes)
notes[#notes+1]={s=.5,e=.75,pitch=72,vel=100,channel=1,selected=true,muted=false}
local drawn=decode(encode(mpe,notes))
local c4=find(drawn,72)
ok(c4.channel~=1 and c4.channel~=2,'drawn note avoids busy channels')
eq(shape(find(drawn,60)),shape(c3))
local neutral=state_at(drawn,c4.channel,c4.on.pos)
ok(neutral.pb==nil or neutral.pb==center,'drawn note is not bent')

-- 9. Duplicating part of a note keeps that part's expression and state.
notes=M.copy(mpe.notes); notes[1].selected=true; notes[2].selected=false
local range=M.duplicate(notes,0,{.375,.9375})
local part=notes[#notes]
eq(part.initial.pb,8192+300,'cut copy starts at the bend it had at the cut')
eq(#part.expr,2,'only the bend and pressure after the cut')
local dup=decode(encode(mpe,notes,to(range[2])))
eq(#dup.notes,3)
local tail
for _,n in ipairs(dup.notes) do if n.pitch==60 and n.on.pos>0 then tail=n end end
eq(state_at(dup,tail.channel,tail.on.pos).pb,8192+300,'copy starts mid-slide')
eq(#tail.expr,4,'seeded bend and pressure, then the rest of the slide')

-- 10. A plain take: one channel, chords, a pitch-bend lane. Nothing is owned;
-- moving notes leaves the channel's bend alone, as before.
raw=stream({{0,on(0,60)},{0,on(0,64)},{240,pb(0,9000)},{480,off(0,60)},{480,off(0,64)},{960,END}})
local plain=decode(raw)
eq(plain.mpe,false,'a chord channel is not MPE')
notes=M.copy(plain.notes); M.move(notes,.25,0,0)
local shifted=decode(encode(plain,notes))
eq(#events_of(shifted,0,240,241),1,'plain bend stays at its time')

-- 11. A monophonic line on one channel with a bend lane is not MPE either.
raw=stream({{0,on(0,60)},{240,pb(0,9000)},{480,off(0,60)},{480,on(0,62)},{900,off(0,62)},{960,END}})
eq(decode(raw).mpe,false,'channel 1 alone is not a member channel')

-- 12. Polyphonic aftertouch and notation follow their note in any take.
local notation=string.char(0xFF,15)..'NOTE 0 60 articulation staccato'
raw=stream({{0,on(0,60)},{0,notation},{0,on(0,64)},{100,string.char(0xA0,60,50)},
  {200,string.char(0xA0,64,70)},{480,off(0,60)},{480,off(0,64)},{960,END}})
local poly=decode(raw)
eq(poly.mpe,false)
eq(#find(poly,60).expr,2,'C3 owns its notation and aftertouch')
notes=M.copy(poly.notes)
for _,n in ipairs(notes) do if n.pitch==60 then n.pitch=62; n.s=n.s+.5; n.e=n.e+.5 end end
local retargeted=decode(encode(poly,notes,to(1)))
local d=find(retargeted,62)
eq(#d.expr,2,'D3 took them along')
local texts,keys={},{}
for _,x in ipairs(d.expr) do
  if x.msg:byte(1)==0xFF then texts[#texts+1]=x.msg:sub(3) else keys[#keys+1]=x.msg:byte(2) end
  ok(x.pos>=480,'moved with the note')
end
eq(texts[1],'NOTE 0 62 articulation staccato','notation names the new pitch')
eq(keys[1],62,'aftertouch names the new key')
eq(#find(retargeted,64).expr,1,'E3 keeps its aftertouch')
eq(encode(poly,M.copy(poly.notes)),raw,'untouched take stays byte exact')

-- 13. Modulation copy/paste does not duplicate what notes carry.
local fragment=A.copy_range(mpe,0,3840)
for _,e in ipairs(fragment.events) do ok(not M.expression(e.msg),'no owned expression in a CC fragment') end
return count
