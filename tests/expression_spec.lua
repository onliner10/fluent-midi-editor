-- MPE expression as breakpoints (expression.lua): what the editor shows for
-- a note's pitch, slide and pressure, and what it writes back.
local root=...
local M=dofile(root..'/MIDI Editor/lib/model.lua')
local X=dofile(root..'/MIDI Editor/lib/expression.lua').new(M)
local count=0
local function eq(a,b,label) count=count+1; assert(a==b,(label or '')..': '..tostring(a)..' ~= '..tostring(b)) end
local function ok(v,label) count=count+1; assert(v,label) end
local function near(a,b,tolerance,label) count=count+1; assert(math.abs(a-b)<=tolerance,(label or '')..': '..tostring(a)..' !~ '..tostring(b)) end
local Q=960
local TICK=1/Q
local from,to=function(t) return t/Q end,function(q) return q*Q end
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
local function find(source,pitch) for _,n in ipairs(source.notes) do if n.pitch==pitch then return n end end end
-- What a synth hears on a channel at a tick: the last value of each dimension.
local function state_at(source,channel,pos)
  local state={}
  for _,e in ipairs(source.events) do
    if e.pos>pos then break end
    local d,c,v=M.expression(e.msg)
    if d and c==channel then state[d]=v end
  end
  return state
end
local function count_of(source,channel,dimension)
  local n=0
  for _,e in ipairs(source.events) do local d,c=M.expression(e.msg); if d==dimension and c==channel then n=n+1 end end
  return n
end
-- Write one dimension of the note with this pitch, as the editor does.
local function edit(source,pitch,dimension,points,known)
  local notes=M.copy(source.notes)
  for _,n in ipairs(notes) do if n.pitch==pitch then n.expr,n.initial=X.write(n,dimension,points,TICK) end end
  return M.decode(M.encode(source,notes,to),from,known)
end

local center=8192
local raw=stream({
  {0,pb(1,center)},{0,at(1,0)},{0,tb(1,64)},{0,on(1,60)},
  {240,pb(1,center+300)},{480,pb(1,center+683)},{600,at(1,90)},{900,off(1,60)},{940,pb(1,center)},
  {960,pb(2,center)},{960,at(2,10)},{960,tb(2,40)},{960,on(2,64)},
  {1200,at(2,100)},{1440,tb(2,110)},{1800,off(2,64)},
  {3840,END}})
local mpe=M.decode(raw,from)
local c3,e3=find(mpe,60),find(mpe,64)
ok(X.editable(c3,mpe),'MPE notes are editable')

-- 1. Held values and jumps are breakpoints; the last value holds to the end.
local bend=X.envelope(c3,'pb')
eq(#bend,5,'start, two jumps')
eq(bend[1].t,0); eq(bend[1].v,center)
eq(bend[2].t,.25); eq(bend[2].v,center); eq(bend[3].t,.25); eq(bend[3].v,center+300)
eq(bend[5].t,.5); eq(bend[5].v,center+683)
eq(X.value(bend,.4),center+300,'held between events')
local slide=X.envelope(e3,'tb')
eq(#slide,3); eq(slide[1].v,40); eq(slide[3].v,110)
ok(X.flat(X.envelope(c3,'tb'),'tb'),'untouched slide is flat')
eq(M.encode(mpe,M.copy(mpe.notes),to),raw,'reading envelopes changes nothing')

-- 2. A ramp is written as small steps and reads back as its two breakpoints.
local ramped=edit(mpe,60,'pb',{{t=0,v=center},{t=.5,v=center+4096}})
local r3=find(ramped,60)
local back=X.envelope(r3,'pb')
eq(#back,2,'ramp reads back as two points')
eq(back[1].v,center); near(back[2].t,.5,2*TICK,'ramp end time'); near(back[2].v,center+4096,8,'ramp end value')
ok(count_of(ramped,r3.channel,'pb')>100,'ramp is smooth')
eq(state_at(ramped,r3.channel,r3.on.pos).pb,center,'starts in tune')
-- The rest of the note's expression and its release tail stay.
eq(#X.envelope(r3,'at'),3,'pressure kept')
eq(find(ramped,60).off.pos,900)
local tail=false
for _,e in ipairs(ramped.events) do local d,c,v=M.expression(e.msg); if d=='pb' and c==r3.channel and e.pos==940 and v==center then tail=true end end
ok(tail,'release tail kept')
-- The other note is untouched.
eq(#X.envelope(find(ramped,64),'at'),3); eq(X.envelope(find(ramped,64),'tb')[3].v,110)

-- A fast slide (a big jump each tick) is a line too, not a staircase of steps.
local fast=X.envelope(find(edit(mpe,60,'pb',{{t=0,v=center},{t=.1,v=center+4096}}),60),'pb')
eq(#fast,2,'fast slide reads back as two points')

-- A controller streaming a slide (an event every 0.04 beat, bigger steps
-- than the tolerance) is a line, not a staircase.
local streamed={{0,pb(1,center-683)},{0,on(1,60)}}
for i=1,12 do streamed[#streamed+1]={i*38,pb(1,center-683+math.floor(683*i/12))} end
streamed[#streamed+1]={900,off(1,60)}; streamed[#streamed+1]={960,pb(2,center)}; streamed[#streamed+1]={960,on(2,64)}
streamed[#streamed+1]={1800,off(2,64)}; streamed[#streamed+1]={3840,END}
local slide_line=X.envelope(find(M.decode(stream(streamed),from),60),'pb')
eq(#slide_line,2,'a streamed slide is one line: '..#slide_line)

-- Simplify turns a dense recording into a few smooth points.
local wobble={{0,pb(1,center)},{0,on(1,60)}}
-- A finger's vibrato with jitter: a little noise on every event.
for i=1,40 do wobble[#wobble+1]={i*20,pb(1,center+math.floor(math.sin(i*20/Q*3)*400)+(i*37)%41-20)} end
wobble[#wobble+1]={900,off(1,60)}; wobble[#wobble+1]={960,pb(2,center)}; wobble[#wobble+1]={960,on(2,64)}
wobble[#wobble+1]={1800,off(2,64)}; wobble[#wobble+1]={3840,END}
local recorded=M.decode(stream(wobble),from)
local dense=X.envelope(find(recorded,60),'pb')
ok(#dense>10,'a jittery recording has many points: '..#dense)
local simple=X.simplify(dense,'pb')
ok(#simple<#dense/2,'simplified to fewer points: '..#dense..' -> '..#simple)
eq(simple[1].t,0)
for t=0,.8,.05 do near(X.value(simple,t),X.value(dense,t),60,'simplified stays close at '..t) end
local smoothed=edit(recorded,60,'pb',simple)
ok(#X.envelope(find(smoothed,60),'pb')<=#simple+1,'reads back as the simplified points')

-- 3. A step stays a step: two events, no ramp.
local stepped=edit(mpe,64,'at',{{t=0,v=0},{t=.25,v=0},{t=.25,v=120}})
local s3=find(stepped,64)
eq(count_of(stepped,s3.channel,'at'),2,'one event per value')
eq(state_at(stepped,s3.channel,s3.on.pos).at,0,'new starting pressure')
eq(state_at(stepped,s3.channel,s3.on.pos+240).at,120,'jump at a quarter of a beat')

-- 4. A new start value becomes the note's starting state, even when the
-- channel was left elsewhere by an earlier note.
local raised=edit(mpe,64,'pb',{{t=0,v=center+1000}})
local u3=find(raised,64)
eq(u3.initial.pb,center+1000); eq(state_at(raised,u3.channel,u3.on.pos).pb,center+1000)
eq(#X.envelope(u3,'pb'),1,'a constant bend is one point')

-- 5. Nothing is written at or after the note-off: it would belong to the next note.
local late=edit(mpe,60,'tb',{{t=0,v=64},{t=2,v=0}})
local l3=find(late,60)
for _,e in ipairs(late.events) do local d,c=M.expression(e.msg); if d=='tb' and c==l3.channel then ok(e.pos<900,'slide before the note-off') end end
eq(#X.envelope(find(late,64),'tb'),3,'E3 slide unaffected')

-- 6. An edited note moves with its new expression.
local notes=M.copy(ramped.notes)
for _,n in ipairs(notes) do n.selected=n.pitch==60 end
M.move(notes,2,0,0)
local moved=M.decode(M.encode(ramped,notes,to,to(4)),from)
local m3=find(moved,60)
eq(m3.on.pos,1920); eq(#X.envelope(m3,'pb'),2,'ramp moved along')
near(X.envelope(m3,'pb')[2].v,center+4096,8)

-- 7. Copies are independent: editing one leaves the other.
notes=M.copy(mpe.notes)
local copy=M.copy(notes[1]); copy.id=nil; copy.s=copy.s+2; copy.e=copy.e+2; notes[#notes+1]=copy
local copied=M.decode(M.encode(mpe,notes,to,to(4)),from)
local first
for _,n in ipairs(copied.notes) do if n.pitch==60 and n.on.pos==0 then first=n end end
notes=M.copy(copied.notes)
for _,n in ipairs(notes) do if n.pitch==60 and n.on.pos==0 then n.expr,n.initial=X.write(n,'pb',{{t=0,v=0}},TICK) end end
local split=M.decode(M.encode(copied,notes,to),from)
for _,n in ipairs(split.notes) do if n.pitch==60 then
  if n.on.pos==0 then eq(X.envelope(n,'pb')[1].v,0) else eq(#X.envelope(n,'pb'),5,'copy keeps its slide') end
end end

-- 8. A plain part becomes MPE: one channel per sounding note, lower zone.
raw=stream({{0,on(0,60)},{0,on(0,64)},{0,on(0,67)},{480,off(0,60)},{480,off(0,64)},{480,off(0,67)},
  {480,on(0,72)},{960,off(0,72)},{100,pb(0,9000)},{3840,END}})
-- (the bend at 100 sorts after the note-offs at 480 above; reorder)
raw=stream({{0,on(0,60)},{0,on(0,64)},{0,on(0,67)},{100,pb(0,9000)},{480,off(0,60)},{480,off(0,64)},{480,off(0,67)},
  {480,on(0,72)},{960,off(0,72)},{3840,END}})
local plain=M.decode(raw,from)
eq(plain.mpe,false)
ok(not X.editable(find(plain,60),plain),'plain notes are not editable')
notes=M.copy(plain.notes)
ok(X.make_mpe(notes),'converted')
local used={}
for _,n in ipairs(notes) do ok(n.channel>=1 and n.channel<=15,'member channel'); if n.s<.5 then ok(not used[n.channel],'own channel'); used[n.channel]=true end end
local converted=M.decode(M.encode(plain,notes,to),from,true)
eq(converted.mpe,true,'a converted clip is MPE')
eq(#converted.notes,4)
ok(X.editable(find(converted,64),converted),'converted notes are editable')
eq(count_of(converted,0,'pb'),1,'the old channel keeps its bend as the zone master')
local bent=edit(converted,64,'pb',{{t=0,v=center},{t=.25,v=center+2000}},true)
local b4=find(bent,64)
eq(#X.envelope(b4,'pb'),2,'converted note bends')
eq(X.envelope(find(bent,60),'pb')[1].v,center,'its neighbour does not')
-- Without the clip's MPE mark, single notes with no expression read as a plain part.
eq(M.decode(M.encode(plain,notes,to),from).mpe,false)

-- 9. Conversion refuses what MPE cannot hold.
notes={}
for i=1,16 do notes[i]={s=0,e=1,pitch=40+i,vel=100,channel=0} end
local done,why=X.make_mpe(notes); ok(not done and why:match('15'),'16 voices do not fit')
notes={{s=0,e=1,pitch=60,vel=100,channel=0},{s=0,e=1,pitch=62,vel=100,channel=3}}
done,why=X.make_mpe(notes); ok(not done and why:match('channels'),'several parts')
-- 10. Writing an envelope back as it is keeps every step and ramp: random
-- envelopes with jumps (two points at one time) survive a write and a read.
math.randomseed(7)
for round=1,200 do
  local dimension=X.DIMENSIONS[round%3+1]
  local maximum=X.MAX[dimension]
  local points,t={{t=0,v=math.random(0,maximum)}},0
  for _=1,math.random(1,6) do
    t=t+math.random(1,8)/16
    if t>=1.9 then break end
    if math.random()<.5 then points[#points+1]={t=t,v=points[#points].v} end
    points[#points+1]={t=t,v=math.random(0,maximum)}
  end
  local source=M.decode(stream({{0,pb(1,center)},{0,on(1,60)},{1920,off(1,60)},{1920,pb(2,center)},{1920,on(2,64)},{2880,off(2,64)},{3840,END}}),from)
  local back=find(edit(source,60,dimension,points),60)
  local shown=X.envelope(back,dimension,TICK)
  local step=dimension=='pb' and 14 or 1.6
  for q=0,1.99,1/32 do
    -- Compare away from jumps, where one tick decides which value shows.
    local near_jump=false
    for k=2,#points do if points[k].t==points[k-1].t and math.abs(q-points[k].t)<.01 then near_jump=true end end
    if not near_jump then near(X.value(shown,q),X.value(points,q),step,'round '..round..' '..dimension..' at '..q) end
  end
end

-- 11. Editing a note keeps the previous note's release tail on its channel.
local tailed=M.decode(stream({{0,pb(1,center)},{0,on(1,60)},{960,off(1,60)},{1100,pb(1,9000)},{1300,pb(1,center)},
  {1920,on(1,62)},{2880,off(1,62)},{2880,pb(2,center)},{2880,on(2,64)},{3000,off(2,64)},{3840,END}}),from)
local tail_edit=edit(tailed,62,'pb',{{t=0,v=center},{t=.5,v=center+1000}})
local kept_tail=0
for _,e in ipairs(tail_edit.events) do local d,c,v=M.expression(e.msg)
  if d=='pb' and c==1 and ((e.pos==1100 and v==9000) or (e.pos==1300 and v==center)) then kept_tail=kept_tail+1 end end
eq(kept_tail,2,'release tail of the previous note kept')

-- 12. Converting a part on another channel moves its controllers to the
-- master channel, so its held bend still reaches every note.
raw=stream({{0,pb(1,10000)},{0,on(1,60)},{0,on(1,64)},{960,off(1,60)},{960,off(1,64)},{3840,END}})
local part=M.decode(raw,from)
notes=M.copy(part.notes)
local converted_ok,channel=X.make_mpe(notes)
ok(converted_ok); eq(channel,1)
local master_raw=X.to_master(part,channel)
ok(master_raw,'controllers to move')
local moved_part=M.decode(M.encode(M.decode(master_raw,from,true),notes,to),from,true)
eq(state_at(moved_part,0,0).pb,10000,'the bend is on the master channel')
for _,n in ipairs(moved_part.notes) do
  local s=state_at(moved_part,n.channel,n.on.pos)
  ok(s.pb==nil or s.pb==center,'member channel '..n.channel..' adds no bend of its own')
end
eq(X.to_master(M.decode(stream({{0,pb(0,9000)},{0,on(0,60)},{960,off(0,60)},{3840,END}}),from),0),nil,'channel 1 is already the master')
return count
