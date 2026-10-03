-- Per-note MPE expression as envelopes, as in Ableton Live's Note Expression
-- view. A note in an MPE clip owns its channel's pitch bend ('pb'), CC74
-- ('tb', Slide) and channel pressure ('at'); model.lua attaches those events
-- to the note (n.expr, n.initial). Here they become breakpoints, and edited
-- breakpoints become events again. Pure logic, times in quarter notes
-- relative to the note start.
local X={}
local M
-- model: model.lua, for the MIDI message helpers.
function X.new(model)
  M=model
  return X
end
X.DIMENSIONS={'pb','tb','at'}
X.NEUTRAL={pb=8192,at=0,tb=64}
X.MAX={pb=16383,at=127,tb=127}
-- Value steps a written ramp takes, and how far a thinned envelope may stray
-- from the MIDI it shows. The tolerance exceeds the step, so a ramp the
-- editor wrote reads back as the two breakpoints it came from.
local QUANTUM={pb=8,at=1,tb=1}
local TOLERANCE={pb=12,at=1.5,tb=1.5}

-- Can this note's expression be edited? Only an MPE note on a channel of its own.
function X.editable(n,source)
  return n and source and source.mpe and n.initial~=nil and not (source.shared or {})[n.channel]
end

-- Keep the points a line through their neighbours cannot stand in for
-- (Ramer-Douglas-Peucker, distance measured in value at the point's time).
local function thin(points,tolerance)
  if #points<3 then return points end
  local keep={[1]=true,[#points]=true}
  local stack={{1,#points}}
  while #stack>0 do
    local span=table.remove(stack); local a,z=points[span[1]],points[span[2]]
    local worst,index=0,nil
    for i=span[1]+1,span[2]-1 do
      local p=points[i]
      local line=z.t>a.t and a.v+(z.v-a.v)*(p.t-a.t)/(z.t-a.t) or (p.t<=a.t and a.v or z.v)
      -- Two points at one time are a jump: keep it.
      if p.t==a.t or p.t==z.t then line=p.t==a.t and a.v or z.v end
      local d=math.abs(p.v-line)
      if d>worst then worst,index=d,i end
    end
    if index and worst>tolerance then
      keep[index]=true; stack[#stack+1]={span[1],index}; stack[#stack+1]={index,span[2]}
    end
  end
  local out={}; for i,p in ipairs(points) do if keep[i] then out[#out+1]=p end end
  return out
end

-- MIDI holds a value until the next event. The breakpoints show that: a value
-- held and then left with a jump is two points; a dense ramp (an event every
-- tick, or steps within the tolerance) is a line. tick: one MIDI tick in
-- quarter notes.
local cache=setmetatable({},{__mode='k'})
function X.envelope(n,dimension,tick)
  tick=tick or 1/960
  local length=n.e-n.s
  local key=dimension..':'..length..':'..tick..':'..tostring(n.initial and n.initial[dimension])
  local list=n.expr or X
  local cached=cache[list] and cache[list][key]
  if cached then return cached end
  local value=n.initial and n.initial[dimension] or X.NEUTRAL[dimension]
  local raw,since={{t=0,v=value}},0
  for _,x in ipairs(n.expr or {}) do
    local d,_,v=M.expression(x.msg)
    if d==dimension and x.dt>1e-9 and x.dt<length-1e-9 and v~=value then
      if math.abs(v-value)>TOLERANCE[dimension] and x.dt-since>1.5*tick then raw[#raw+1]={t=x.dt,v=value} end
      raw[#raw+1]={t=x.dt,v=v}; value=v; since=x.dt
    end
  end
  raw[#raw+1]={t=length,v=value}
  local points=thin(raw,TOLERANCE[dimension])
  -- The value after the last breakpoint holds to the end of the note.
  if #points>1 and points[#points].v==points[#points-1].v then points[#points]=nil end
  cache[list]=cache[list] or {}; cache[list][key]=points
  return points
end
-- The envelope's value at time t (linear between breakpoints).
function X.value(points,t)
  if t<=points[1].t then return points[1].v end
  for i=2,#points do
    local a,z=points[i-1],points[i]
    if t<z.t then return z.t>a.t and a.v+(z.v-a.v)*(t-a.t)/(z.t-a.t) or z.v end
  end
  return points[#points].v
end
-- Whether a note's envelope differs from the neutral value anywhere.
function X.flat(points,dimension)
  return #points==1 and points[1].v==X.NEUTRAL[dimension]
end

-- Fewer points for a dense recording: steps become a smooth line within a
-- few times the display tolerance (about a quarter semitone of bend at a
-- 48-semitone range, or 6 of 127). For an envelope to write with X.write.
function X.simplify(points,dimension)
  local events={}
  for k,p in ipairs(points) do
    -- A held value before a jump is the first of two points at one time.
    local nextp=points[k+1]
    if not (nextp and nextp.t==p.t) then events[#events+1]={t=p.t,v=p.v} end
  end
  if #events==0 then return {{t=0,v=points[1].v}} end
  events[1].t=0
  return thin(events,4*TOLERANCE[dimension])
end

-- Replace one dimension of a note's expression with breakpoints. tick: one
-- MIDI tick in quarter notes, for ramp resolution and to keep the last event
-- before the note-off. Returns the new expression list and starting state;
-- the note itself is not changed.
function X.write(n,dimension,points,tick)
  local length=n.e-n.s
  tick=tick or 1/960
  local last_time=math.max(0,length-tick)
  local sorted={}
  for _,p in ipairs(points) do
    sorted[#sorted+1]={t=M.clamp(p.t,0,last_time),v=math.floor(M.clamp(p.v,0,X.MAX[dimension])+.5)}
  end
  table.sort(sorted,function(a,b) return a.t<b.t end)
  if #sorted==0 then sorted[1]={t=0,v=X.NEUTRAL[dimension]} end
  sorted[1].t=0
  -- Events on the tick grid; a later event on the same tick wins.
  local times,values={}, {}
  local function emit(t,v)
    local k=math.floor(t/tick+.5)
    if times[#times]==k then values[#values]=v else times[#times+1]=k; values[#values+1]=v end
  end
  for i,a in ipairs(sorted) do
    emit(a.t,a.v)
    local z=sorted[i+1]
    if z and z.t>a.t and z.v~=a.v then
      local steps=math.min(math.floor(math.abs(z.v-a.v)/QUANTUM[dimension]),math.floor((z.t-a.t)/tick+1e-6))
      for j=1,steps-1 do
        emit(a.t+(z.t-a.t)*j/steps,math.floor(a.v+(z.v-a.v)*j/steps+.5))
      end
    end
  end
  local kept,removed={},false
  local length_end=length-1e-9
  for _,x in ipairs(n.expr or {}) do
    local d=M.expression(x.msg)
    if d==dimension and x.dt<length_end then removed=true
    elseif removed and M.curve_data(x.msg) then -- the removed event's curve shape
    else kept[#kept+1]=x; removed=false end
  end
  local previous
  for i,k in ipairs(times) do
    if values[i]~=previous then
      kept[#kept+1]={dt=k*tick,flags=0,msg=M.expression_message(dimension,n.channel,values[i])}
      previous=values[i]
    end
  end
  table.sort(kept,function(a,b) return a.dt<b.dt end)
  -- model.encode writes an edited list instead of the source's.
  kept.edited=true
  local initial={}
  for k,v in pairs(n.initial or {}) do initial[k]=v end
  initial[dimension]=values[1]
  return setmetatable(kept,M.shared),setmetatable(initial,M.shared)
end

-- Spread the notes of a plain one-channel part over MPE member channels
-- 2-16 (lower zone), so each sounding note can carry its own expression.
-- Controllers on the old channel stay there; on channel 1 they become the
-- zone's master controllers. Returns nil and a reason when it cannot.
function X.make_mpe(notes)
  local channel
  for _,n in ipairs(notes) do
    if channel and n.channel~=channel then return nil,'Notes use several MIDI channels. MPE needs a single part.' end
    channel=n.channel
  end
  local order={}; for i,n in ipairs(notes) do order[i]=n end
  table.sort(order,function(a,b) if a.s~=b.s then return a.s<b.s end; return a.pitch<b.pitch end)
  local free_since={}
  for c=1,15 do free_since[c]=-math.huge end
  for _,n in ipairs(order) do
    local best
    for c=1,15 do
      if free_since[c]<=n.s+1e-9 and (not best or free_since[c]<free_since[best]) then best=c end
    end
    if not best then return nil,'More than 15 notes sound at once; MPE has 15 voice channels.' end
    n.channel=best; free_since[best]=n.e; n.initial=setmetatable({},M.shared)
  end
  return true
end
return X
