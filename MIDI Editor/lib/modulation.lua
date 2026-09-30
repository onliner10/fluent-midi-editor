-- Clip-owned modulation. Editable knots are MIDI text events; ordinary CCs are
-- the playback representation. Both travel with source copies, pooling and RPP.
-- No Lua code is evaluated from MIDI metadata. Time always lives in event PPQ.
local A={prefix=string.char(0xFF,1)..'LMOD1|',resolution=96}
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function finite(x) return type(x)=='number' and x==x and math.abs(x)<1e12 end
local function copy(v) if type(v)~='table' then return v end; local o={}; for k,x in pairs(v) do o[k]=copy(x) end; return o end
A.copy=copy
function A.key(channel,cc) return channel..':'..cc end
local function hex(s) return (s or ''):gsub('.',function(c) return string.format('%02x',c:byte()) end) end
local function unhex(s)
  if #s%2~=0 or s:find('[^%da-fA-F]') or #s>8192 then return '' end
  return (s:gsub('%x%x',function(c) return string.char(tonumber(c,16)) end))
end
function A.meta(msg)
  if msg:sub(1,#A.prefix)~=A.prefix then return end
  local fields={}; for value in (msg:sub(#A.prefix+1)..'|'):gmatch('(.-)|') do fields[#fields+1]=value end
  local ch,cc=tonumber(fields[2]),tonumber(fields[3])
  if not ch or ch%1~=0 or ch<0 or ch>15 or not cc or cc%1~=0 or cc<0 or cc>119 then return end
  return fields,A.key(ch,cc),ch,cc
end
-- CCs a note owns (MPE timbre) move with that note, not with a lane.
function A.cc_key(event)
  if event.owner then return end
  local a,b=event.msg:byte(1,2)
  if #event.msg==3 and a&0xF0==0xB0 and b<120 then return A.key(a&15,b),a&15,b end
end
function A.sort(points)
  for i,p in ipairs(points) do p.order=i end
  table.sort(points,function(a,b) return a.t==b.t and a.order<b.order or a.t<b.t end)
end
function A.controls(lane,i)
  local ps=lane.points; local a,b=ps[i],ps[i+1]; local dx,dy=b.t-a.t,b.v-a.v
  if a.c1 and a.c2 then return a.c1,a.c2 end
  local function slope(p,index)
    local weight=p.kind==2 and 1 or p.kind==1 and .5 or 0
    local prev,nextp=ps[math.max(1,index-1)],ps[math.min(#ps,index+1)]
    local tangent=(nextp.v-prev.v)/math.max(1e-12,nextp.t-prev.t)
    return dy*(1-weight)+tangent*dx*weight
  end
  return clamp(a.v+slope(a,i)/3+(a.bend or 0),0,1),clamp(b.v-slope(b,i+1)/3+(a.bend or 0),0,1)
end
function A.segment(lane,i,t)
  local a,b=lane.points[i],lane.points[i+1]
  if a.kind==3 then return a.v end
  local c,d=A.controls(lane,i); local u=1-t
  return u^3*a.v+3*u*u*t*c+3*u*t*t*d+t^3*b.v
end
function A.value(lane,t)
  local ps=lane.points
  if #ps==0 then return lane.baseline or .5 end
  if t<ps[1].t then return ps[1].v end
  for i=1,#ps-1 do if t<ps[i+1].t-1e-10 then return A.segment(lane,i,clamp((t-ps[i].t)/(ps[i+1].t-ps[i].t),0,1)) end end
  return ps[#ps].v
end
function A.read(source,from_ppq)
  from_ppq=from_ppq or function(x) return x end
  local lanes,bykey={},{}
  local function get(key,ch,cc)
    if not bykey[key] then
      local lane={key=key,channel=ch,cc=cc,label='CC '..cc,points={},native={},managed=false,mode='curve'}
      lanes[#lanes+1]=lane; bykey[key]=lane
    end
    return bykey[key]
  end
  for _,e in ipairs(source.events) do
    local fields,key,ch,cc=A.meta(e.msg)
    if fields then
      local lane=get(key,ch,cc)
      if fields[1]=='L' and #fields>=9 then
        lane.managed=true; lane.label=unhex(fields[4]); lane.fx_guid=unhex(fields[5]); lane.param_ident=unhex(fields[6])
        lane.param_name=unhex(fields[7]); lane.mode=fields[8]=='steps' and 'steps' or 'curve'; lane.baseline=clamp(tonumber(fields[9]) or .5,0,1)
      elseif fields[1]=='P' and #fields>=7 then
        local value,kind,bend,offset=tonumber(fields[4]),tonumber(fields[5]),tonumber(fields[6]),tonumber(fields[7])
        if finite(value) and value>=0 and value<=1 and kind and kind%1==0 and kind>=0 and kind<=3 and finite(bend) and math.abs(bend)<=1 and (offset==0 or offset==1) then
          local p={t=from_ppq(e.pos+offset),v=value,kind=kind,bend=bend,selected=false}
          local c1,c2=tonumber(fields[8]),tonumber(fields[9])
          if finite(c1) and finite(c2) and c1>=0 and c1<=1 and c2>=0 and c2<=1 then p.c1,p.c2=c1,c2 end
          lane.points[#lane.points+1]=p
        end
      end
    else
      key,ch,cc=A.cc_key(e)
      if key then
        local lane=get(key,ch,cc); local shape=(e.flags>>4)&15
        lane.native[#lane.native+1]={t=from_ppq(e.pos),v=e.msg:byte(3)/127,kind=shape==0 and 3 or 0,bend=0,flags=e.flags}
        if shape>1 then lane.complex_native=true end
      end
    end
  end
  for _,lane in ipairs(lanes) do
    if not lane.managed then lane.points=copy(lane.native) end
    A.sort(lane.points)
  end
  table.sort(lanes,function(a,b) return a.channel==b.channel and a.cc<b.cc or a.channel<b.channel end)
  return lanes,bykey
end
local function pack(events)
  for i,e in ipairs(events) do e.order=i end
  table.sort(events,function(a,b) return a.pos==b.pos and a.order<b.order or a.pos<b.pos end)
  local parts,last={},0
  for _,e in ipairs(events) do
    local pos=math.floor(e.pos+.5); local delta=pos-last
    while delta>0x7FFFFFFF do parts[#parts+1]=string.pack('i4Bs4',0x7FFFFFFF,0,''); delta=delta-0x7FFFFFFF end
    parts[#parts+1]=string.pack('i4Bs4',delta,e.flags,e.msg); last=pos
  end
  return table.concat(parts)
end
A.pack=pack
local function header(lane)
  return A.prefix..table.concat({'L',lane.channel,lane.cc,hex(lane.label),hex(lane.fx_guid),hex(lane.param_ident),hex(lane.param_name),lane.mode or 'curve',lane.baseline or .5},'|')
end
local function knot(lane,p,pos,ending)
  local offset=pos==ending and 1 or 0
  local message=A.prefix..string.format('P|%d|%d|%.17g|%d|%.17g|%d',lane.channel,lane.cc,p.v,p.kind or 0,p.bend or 0,offset)
  if p.c1 and p.c2 then message=message..string.format('|%.17g|%.17g',p.c1,p.c2) end
  return {pos=pos-offset,flags=0,msg=message}
end
function A.samples(lane,to_ppq,end_ppq)
  local result={}; local ps=copy(lane.points); A.sort(ps)
  local normalized=copy(lane); normalized.points=ps
  local previous,emitted=nil,{}
  local function add(q,v,force)
    local pos=math.floor(to_ppq(q)+.5); if pos>=end_ppq then return end
    local value=clamp(math.floor(v*127+.5),0,127)
    if emitted[pos] then emitted[pos].msg=string.char(0xB0|lane.channel,lane.cc,value); previous=value; return end
    if force or value~=previous then
      local e={pos=pos,flags=0,msg=string.char(0xB0|lane.channel,lane.cc,value)}
      result[#result+1]=e; emitted[pos]=e; previous=value
    end
  end
  for i,p in ipairs(ps) do
    add(p.t,p.v,true)
    local b=ps[i+1]
    if b and b.t>p.t and p.kind~=3 then
      local count=math.max(1,math.ceil((b.t-p.t)*A.resolution-1e-8))
      assert(count<=1000000,'Modulation is too long. Split it into shorter phrases.')
      for k=1,count-1 do add(p.t+(b.t-p.t)*k/count,A.segment(normalized,i,k/count)) end
    end
  end
  return result
end
function A.matches_playback(lane,source,from_ppq,to_ppq)
  local actual={}
  for _,e in ipairs(source.events) do if A.cc_key(e)==lane.key then actual[#actual+1]=e end end
  if #actual==0 then return #lane.points==0 end
  local tolerance=2/127+1e-8
  for _,e in ipairs(actual) do
    if e.flags&0xF2~=0 or math.abs(e.msg:byte(3)/127-A.value(lane,from_ppq(e.pos)))>tolerance then return false end
  end
  local index=1
  for _,e in ipairs(A.samples(lane,to_ppq,source.end_ppq)) do
    while actual[index+1] and actual[index+1].pos<=e.pos do index=index+1 end
    if actual[index].pos>e.pos or math.abs(actual[index].msg:byte(3)-e.msg:byte(3))>2 then return false end
  end
  return true
end
function A.write(source,changes,to_ppq,end_ppq)
  end_ppq=math.floor((end_ppq or source.end_ppq)+.5)
  local replacement,generated={},{}
  for _,lane in ipairs(changes) do
    assert(lane.channel%1==0 and lane.channel>=0 and lane.channel<16 and lane.cc%1==0 and lane.cc>=0 and lane.cc<120,'Invalid CC')
    local key=A.key(lane.channel,lane.cc); assert(not replacement[key],'Duplicate CC lane'); replacement[key]=true
    if not lane.deleted then
      assert(#lane.points<=16384,'Too many modulation points')
      for _,p in ipairs(lane.points) do assert(finite(p.t) and finite(p.v) and p.v>=0 and p.v<=1 and finite(p.bend or 0) and math.abs(p.bend or 0)<=1,'Invalid modulation point') end
      generated[#generated+1]={pos=0,flags=0,msg=header(lane)}
      for _,p in ipairs(lane.points) do
        local pos=math.floor(to_ppq(p.t)+.5)
        -- End knots are physically inside the source, so native repeat/trim
        -- operations carry them. +1 reconstructs the exact boundary time.
        generated[#generated+1]=knot(lane,p,pos,end_ppq)
      end
      for _,e in ipairs(A.samples(lane,to_ppq,end_ppq)) do generated[#generated+1]=e end
    end
  end
  local retained,remove_bezier={},false
  for i,e in ipairs(source.events) do
    local _,key=A.meta(e.msg); local cc=A.cc_key(e)
    local bezier=e.msg:sub(1,7)==string.char(0xFF,15)..'CCBZ '
    local drop=(key and replacement[key]) or (cc and replacement[cc]) or (bezier and remove_bezier)
    if not bezier then remove_bezier=cc and replacement[cc] end
    if not drop then
      local event=copy(e)
      if i==#source.events and (#e.msg==0 or (#e.msg==3 and e.msg:byte(1)&0xF0==0xB0 and e.msg:byte(2)==123)) then event.pos=end_ppq end
      retained[#retained+1]=event
    end
  end
  -- Put CC before note-on at the same tick, while retaining the original order
  -- of all unrelated events (including their CCBZ attachments).
  for _,e in ipairs(retained) do generated[#generated+1]=e end
  return pack(generated)
end
function A.new_lane(channel,cc,start,finish,value,label)
  return {key=A.key(channel,cc),channel=channel,cc=cc,label=label or 'CC '..cc,managed=true,mode='curve',baseline=value or .5,
    points={{t=start,v=value or .5,kind=0,bend=0},{t=finish,v=value or .5,kind=0,bend=0}}}
end
function A.paint(lane,a,z,value)
  local after=A.value(lane,z); local out={}; local ps=lane.points
  local function append(part) for _,p in ipairs(part.points) do out[#out+1]=p end end
  if ps[1] and ps[1].t<a then append(A.clip(lane,ps[1].t,a)) end
  out[#out+1]={t=a,v=clamp(value,0,1),kind=3,bend=0}
  if ps[#ps] and ps[#ps].t>z then append(A.clip(lane,z,ps[#ps].t))
  else out[#out+1]={t=z,v=after,kind=3,bend=0} end
  lane.points=out; A.sort(out)
end
-- Copy real CCs, attached native curve data and our metadata. This preserves
-- playback exactly rather than rebuilding a selected curve from screen pixels.
function A.copy_range(source,a,z,keys)
  local events,last_cc={},false
  local lanes=A.read(source)
  -- Seed each CC with its value at the selection start. It must not inherit
  -- an unrelated previous clip's controller state when pasted elsewhere.
  for _,lane in ipairs(lanes) do if not keys or keys[lane.key] then
    local previous
    for _,p in ipairs(lane.native) do if p.t<=a then previous=p end end
    if previous and previous.t<a then events[#events+1]={pos=0,flags=0,msg=string.char(0xB0|lane.channel,lane.cc,math.floor(previous.v*127+.5))} end
    if lane.managed then
      events[#events+1]={pos=0,flags=0,msg=header(lane)}
      local clipped=A.clip(lane,a,z)
      for _,p in ipairs(clipped.points) do events[#events+1]=knot(lane,p,math.floor(p.t-a+.5),math.floor(z-a+.5)) end
    end
  end end
  for _,e in ipairs(source.events) do
    local fields,meta=A.meta(e.msg); local cc=A.cc_key(e)
    local bezier=e.msg:sub(1,7)==string.char(0xFF,15)..'CCBZ '
    if not bezier then last_cc=cc and (not keys or keys[cc]) end
    local allowed=cc and (not keys or keys[cc]) or bezier and last_cc
    if allowed and e.pos>=a and e.pos<z then
      local c=copy(e); c.pos=c.pos-a; events[#events+1]=c
    end
  end
  return {events=events,length=z-a}
end
function A.clip(lane,a,z)
  local clipped=copy(lane); local cuts={{t=a,v=A.value(lane,a)}}
  for _,p in ipairs(lane.points) do if p.t>a and p.t<z then cuts[#cuts+1]={t=p.t,v=p.v} end end
  local finish_value=A.value(lane,z)
  for _,p in ipairs(lane.points) do if p.t==z then finish_value=p.v; break end end
  cuts[#cuts+1]={t=z,v=finish_value}; clipped.points={}
  for i,cut in ipairs(cuts) do
    local t=cut.t; local p={t=t,v=cut.v,kind=0,bend=0}; clipped.points[#clipped.points+1]=p
    if cuts[i+1] then
      local index
      for j=1,#lane.points-1 do if t>=lane.points[j].t and t<lane.points[j+1].t then index=j end end
      if index then
        local start,finish=lane.points[index],lane.points[index+1]
        p.kind=start.kind
        if start.kind~=3 then
          local c1,c2=A.controls(lane,index); local span=finish.t-start.t
          local u,v=(t-start.t)/span,(cuts[i+1].t-start.t)/span
          local function derivative(x) return 3*((1-x)^2*(c1-start.v)+2*(1-x)*x*(c2-c1)+x*x*(finish.v-c2)) end
          p.c1=clamp(A.segment(lane,index,u)+derivative(u)*(v-u)/3,0,1)
          p.c2=clamp(A.segment(lane,index,v)-derivative(v)*(v-u)/3,0,1)
        end
      else p.kind=3 end
    end
  end
  return clipped
end
function A.insert_range(source,fragment,destination,end_ppq)
  local events={}; local keys={}; local rebuilt={}
  local _,original=A.read(source); local _,incoming=A.read({events=fragment.events})
  local ending=math.max(source.end_ppq,end_ppq or source.end_ppq)
  for key,lane in pairs(incoming) do local old=original[key]
    if lane.managed and old and old.managed then
      -- Preserve the two outside curve pieces analytically. Two knots at the
      -- same time represent a discontinuity without bending the previous part.
      local merged=copy(old); merged.points={}; rebuilt[key]=true
      local function append(part,shift)
        for _,p in ipairs(part.points) do local c=copy(p); c.t=c.t+(shift or 0); merged.points[#merged.points+1]=c end
      end
      if old.points[1] and old.points[1].t<destination then append(A.clip(old,old.points[1].t,destination)) end
      append(lane,destination)
      local finish=destination+fragment.length
      if old.points[#old.points] and old.points[#old.points].t>finish then append(A.clip(old,finish,old.points[#old.points].t)) end
      events[#events+1]={pos=0,flags=0,msg=header(merged)}
      for _,p in ipairs(merged.points) do events[#events+1]=knot(merged,p,math.floor(p.t+.5),ending) end
      if finish<source.end_ppq then
        local previous
        for _,p in ipairs(old.native) do if p.t<=finish then previous=p end end
        if previous and previous.t<finish then events[#events+1]={pos=finish,flags=0,msg=string.char(0xB0|old.channel,old.cc,math.floor(previous.v*127+.5))} end
      end
    end
  end
  for _,e in ipairs(fragment.events) do local _,meta=A.meta(e.msg); local cc=A.cc_key(e); if meta or cc then keys[meta or cc]=true end end
  local remove_bezier=false
  for i,e in ipairs(source.events) do
    local _,meta=A.meta(e.msg); local cc=A.cc_key(e); local bezier=e.msg:sub(1,7)==string.char(0xFF,15)..'CCBZ '
    local in_range=e.pos>=destination and e.pos<destination+fragment.length
    local drop=meta and rebuilt[meta] or in_range and ((meta and keys[meta]) or (cc and keys[cc]) or (bezier and remove_bezier))
    if not bezier then remove_bezier=cc and keys[cc] end
    if not drop then local c=copy(e); if i==#source.events then c.pos=math.max(c.pos,end_ppq or c.pos) end; events[#events+1]=c end
  end
  for _,e in ipairs(fragment.events) do local _,meta=A.meta(e.msg)
    if not (meta and rebuilt[meta]) then local c=copy(e); c.pos=c.pos+destination; events[#events+1]=c end
  end
  return pack(events)
end
function A.retime(fragment,convert)
  local result=copy(fragment)
  for _,e in ipairs(result.events) do
    local fields=A.meta(e.msg); local offset=fields and fields[1]=='P' and tonumber(fields[7]) or 0
    e.pos=convert(e.pos+offset)-offset
  end
  result.length=convert(fragment.length)-convert(0)
  return result
end
return A
