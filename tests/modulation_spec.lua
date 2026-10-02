local root=...
local dir=root..'/MIDI Editor/lib/'
local A,M,P=dofile(dir..'modulation.lua'),dofile(dir..'model.lua'),dofile(dir..'phrase.lua')
local count=0
local function check(v,message) count=count+1; assert(v,message) end
local function close(a,b,message) check(math.abs(a-b)<1e-6,message or (tostring(a)..' ~= '..tostring(b))) end
local function e(pos,msg,flags) return {pos=pos,msg=msg,flags=flags or 0} end
local source=M.decode(A.pack({e(0,string.char(0x90,60,100)),e(20,string.char(0xB1,1,32),0x50),
  e(20,string.char(0xFF,15)..'CCBZ '..string.char(0,0,0,0,0)),e(400,string.char(0x80,60,27)),
  e(600,string.char(0xFF,1)..'user text'),e(960,string.char(0xB0,123,0))}),function(p) return p/240 end)
local to=function(q) return q*240 end
local from=function(p) return p/240 end
local lane=A.new_lane(0,20,0,4,.3,'Synth | cutoff / zażółć')
lane.points={{t=0,v=.1,kind=0,bend=.3},{t=2,v=.9,kind=2,bend=0},{t=4,v=.2,kind=0,bend=0}}
lane.fx_guid='{abc}'; lane.param_ident=':cutoff'; lane.param_name='Filter cutoff'
local raw=A.write(source,{lane},to,960)
local result=M.decode(raw,from); local lanes,bykey=A.read(result,from); local got=bykey['0:20']
check(got.managed and #got.points==3,'knots restored'); check(got.label==lane.label,'UTF-8 metadata escaping')
check(got.fx_guid==lane.fx_guid and got.param_ident==lane.param_ident,'target copied with source')
check(#got.native>40,'curve rendered as playable CC'); check(#result.notes==1 and result.notes[1].off.msg:byte(3)==27,'notes unaffected')
for _,wanted in ipairs(source.events) do
  local found=false; for _,ev in ipairs(result.events) do if ev.pos==wanted.pos and ev.flags==wanted.flags and ev.msg==wanted.msg then found=true end end
  check(found,'unrelated MIDI must survive byte-for-byte')
end
for _,p in ipairs(got.points) do close(p.t, lane.points[_].t); close(p.v,lane.points[_].v) end
check(A.write(result,{got},to,960)==raw,'no-op write stable')
local note_edit=M.copy(result.notes); note_edit[1].vel=55
local edited=M.decode(M.encode(result,note_edit,to),from)
local _,note_lanes=A.read(edited,from); close(A.value(note_lanes['0:20'],1),A.value(got,1),'note edit retains modulation')
local loop=M.decode(P.materialize(result,0,1920),from)
local _,loops=A.read(loop,from); check(#loops['0:20'].points==6,'native loop materialization carries end knots')
for i=0,39 do close(A.value(loops['0:20'],i/10),A.value(loops['0:20'],i/10+4),'repeated curve shape') end
local fragment=A.copy_range(result,0,960)
local dup=M.decode(A.insert_range(result,fragment,960,1920),from)
local _,copies=A.read(dup,from); check(#copies['0:20'].points==6,'Ctrl+D carries editable knots')
for i=0,39 do close(A.value(copies['0:20'],i/10),A.value(copies['0:20'],i/10+4),'duplicate curve equality') end
local partial=A.copy_range(result,180,780)
local pasted=M.decode(A.insert_range(M.decode(A.pack({e(960,string.char(0xB0,123,0))})),partial,0,960),from)
local _,partial_lanes=A.read(pasted,from); check(partial_lanes['0:20'].managed,'partial copy carries header')
for i=0,24 do close(A.value(partial_lanes['0:20'],i/10),A.value(got,.75+i/10),'Bezier subdivision survives partial copy') end
local step=A.copy(got); A.paint(step,1,1.25,.8)
close(A.value(step,1),.8); close(A.value(step,1.24),.8); close(A.value(step,1.25),A.value(got,1.25))
for i=0,99 do close(A.value(step,i/100),A.value(got,i/100),'step changed the preceding curve') end
for i=125,400 do close(A.value(step,i/100),A.value(got,i/100),'step changed the following curve') end
check(#A.read(M.decode(A.write(result,{{channel=0,cc=20,deleted=true}},to,960)),from)==1,'delete only this lane')
local extended=M.decode(P.duplicate(result,0,960,1920),from); local _,extensions=A.read(extended,from)
check(#extensions['0:20'].points==6,'phrase extension retains knots')
local malformed=e(0,A.prefix..'P|0|20|nan|0|0|0')
local parsed=A.read(M.decode(A.pack({malformed,e(20,string.char(0xB0,123,0))})))
check(#parsed[1].points==0,'invalid metadata not executable/not a point')
local x=A.clip(got,.5,3.5)
for i=0,100 do close(A.value(x,.5+3*i/100),A.value(got,.5+3*i/100),'analytic curve clipping') end
local beats=A.retime(fragment,function(pos) return pos/240 end)
local new_ticks=A.retime(beats,function(q) return q*960 end)
local rate=M.decode(A.insert_range(M.decode(A.pack({e(3840,string.char(0xB0,123,0))})),new_ticks,0,3840),function(p) return p/960 end)
local _,rate_lanes=A.read(rate,function(p) return p/960 end)
close(rate_lanes['0:20'].points[3].t,4,'boundary metadata survives PPQ conversion')
check(A.matches_playback(got,result,from,to),'own CC recognized')
check(A.matches_playback(copies['0:20'],dup,from,to),'duplicated CC recognized')
local external=M.copy(result)
for _,ev in ipairs(external.events) do if A.cc_key(ev)=='0:20' then ev.msg=string.char(0xB0,20,0); break end end
check(not A.matches_playback(got,external,from,to),'external CC change detected')
local replacement=A.copy_range(result,0,240)
local middle=M.decode(A.insert_range(result,replacement,480,960),from)
local _,middle_lanes=A.read(middle,from)
for i=0,19 do close(A.value(middle_lanes['0:20'],i/10),A.value(got,i/10),'paste changed preceding curve') end
for i=30,39 do close(A.value(middle_lanes['0:20'],i/10),A.value(got,i/10),'paste changed following curve') end
for i=0,9 do close(A.value(middle_lanes['0:20'],2+i/10),A.value(got,i/10),'paste changed inserted curve') end
check(A.matches_playback(middle_lanes['0:20'],middle,from,to),'partial paste falsely marked stale')
local discontinuity=A.clip(middle_lanes['0:20'],0,4)
for i=0,399 do close(A.value(discontinuity,i/100),A.value(middle_lanes['0:20'],i/100),'clipping lost a discontinuity') end
return count
