-- Pure MIDI editing logic. No REAPER/UI dependencies; all times are quarter notes.
local M = {}
function M.clamp(x,a,b) return math.max(a,math.min(b,x)) end
function M.velocity_color(base,velocity)
  local gain=.30+.70*(M.clamp(velocity,1,127)-1)/126
  local r=math.floor(((base>>24)&255)*gain+.5)
  local g=math.floor(((base>>16)&255)*gain+.5)
  local b=math.floor(((base>>8)&255)*gain+.5)
  return (r<<24)|(g<<16)|(b<<8)|255
end
function M.copy(value)
  if type(value)~='table' then return value end
  local out={}; for k,v in pairs(value) do out[k]=M.copy(v) end; return out
end
function M.snap(x,grid) return grid>0 and math.floor(x/grid+0.5)*grid or x end
function M.floor(x,grid) return grid>0 and math.floor(x/grid+1e-8)*grid or x end
function M.drag_delta(anchor,delta,grid)
  -- Snap the absolute edge, not the distance travelled. Re-enabling snap after
  -- a free move must remove its offset; relative spacing inside a chord stays.
  return grid and grid>0 and M.snap(anchor+delta,grid)-anchor or delta
end
function M.nudge_delta(anchor,direction,grid)
  if direction>0 then return (math.floor(anchor/grid+1e-8)+1)*grid-anchor end
  return (math.ceil(anchor/grid-1e-8)-1)*grid-anchor
end
function M.selection_range(anchor,current,grid,moved)
  -- IsMouseDragging is false on mouse-up: the gesture must retain its moved bit.
  if not moved then return nil end
  local a,b=math.max(0,math.min(anchor,current)),math.max(anchor,current)
  if grid and grid>0 then a=M.floor(a,grid); b=math.ceil(b/grid-1e-8)*grid end
  return b>a and {a,b} or nil
end
function M.pitch_name(p)
  return ({'C','C#','D','D#','E','F','F#','G','G#','A','A#','B'})[p%12+1]..(math.floor(p/12)-2)
end
function M.selected(notes)
  local out={}; for _,n in ipairs(notes) do if n.selected then out[#out+1]=n end end; return out
end
function M.bounds(notes,selected)
  local a,b,lo,hi
  for _,n in ipairs(notes) do if not selected or n.selected then
    a=a and math.min(a,n.s) or n.s; b=b and math.max(b,n.e) or n.e
    lo=lo and math.min(lo,n.pitch) or n.pitch; hi=hi and math.max(hi,n.pitch) or n.pitch
  end end
  return a,b,lo,hi
end
function M.move(notes,dt,dp,minimum,maximum)
  local a,b,lo,hi=M.bounds(notes,true); if not a then return end
  dt=math.max(dt,(minimum or 0)-a)
  if maximum then dt=math.min(dt,maximum-b) end
  dp=M.clamp(dp,-lo,127-hi)
  for _,n in ipairs(notes) do if n.selected then n.s=n.s+dt; n.e=n.e+dt; n.pitch=n.pitch+dp end end
end
function M.resize(notes,delta,edge,minimum,maximum,minlen)
  minlen=minlen or 1/960
  -- One common delta preserves the lengths/spacing of a multi-note selection.
  local lower,upper=-math.huge,math.huge
  for _,n in ipairs(notes) do if n.selected then
    if edge=='left' then lower=math.max(lower,(minimum or 0)-n.s); upper=math.min(upper,n.e-n.s-minlen)
    else lower=math.max(lower,minlen-(n.e-n.s)); if maximum then upper=math.min(upper,maximum-n.e) end end
  end end
  delta=M.clamp(delta,lower,upper)
  for _,n in ipairs(notes) do if n.selected then
    if edge=='left' then n.s=n.s+delta else n.e=n.e+delta end
  end end
end
function M.duplicate(notes,grid,range)
  local a,b=M.bounds(notes,true); if not a then return nil end
  if range and range[2]>range[1] then a,b=range[1],range[2]
  elseif grid>0 then a=M.floor(a,grid); b=math.ceil(b/grid-1e-8)*grid end
  if b<=a then return nil end
  local copies={}
  for _,n in ipairs(notes) do if n.selected then
    local s,e=math.max(n.s,a),math.min(n.e,b)
    if e>s then local c=M.copy(n); c.id=nil; c.s=s+b-a; c.e=e+b-a; copies[#copies+1]=c end
  end end
  if #copies==0 then return nil end
  for _,n in ipairs(notes) do n.selected=false end
  for _,n in ipairs(copies) do notes[#notes+1]=n end
  return {b,b+b-a}
end
-- Keep opaque events (CC, pitch bend, text, sysex, notation) and note-off velocity.
-- IDs refer to original on/off events, so sorting never changes edit identity.
function M.decode(raw,from_ppq)
  from_ppq=from_ppq or function(x) return x end
  local events,notes,queues={}, {}, {}; local cursor,pos=1,0
  while cursor<=#raw do
    local delta,flags,msg; delta,flags,msg,cursor=string.unpack('i4Bs4',raw,cursor)
    pos=pos+delta
    local event={pos=pos,flags=flags,msg=msg,order=#events+1}; events[#events+1]=event
    if #msg>=3 then
      local status,pitch,vel=msg:byte(1,3); local kind,channel=status&0xF0,status&15
      local key=channel*128+pitch
      if kind==0x90 and vel>0 then
        local n={id=#notes+1,s=from_ppq(pos),pitch=pitch,vel=vel,channel=channel,
          selected=flags&1~=0,muted=flags&2~=0,on=event}
        notes[#notes+1]=n; queues[key]=queues[key] or {}; table.insert(queues[key],n)
      elseif kind==0x80 or (kind==0x90 and vel==0) then
        local q=queues[key]
        if q and #q>0 then local n=table.remove(q,1); n.e=from_ppq(pos); n.off=event end
      end
    end
  end
  local paired={}
  for _,n in ipairs(notes) do if n.off and n.e>n.s then
    n.on.note_id=n.id; n.on.is_on=true; n.off.note_id=n.id; paired[#paired+1]=n
  end end
  return {events=events,notes=paired,end_ppq=pos,raw=raw}
end
function M.encode(source,notes,to_ppq,end_ppq)
  to_ppq=to_ppq or function(x) return x end
  local changed,out={},{}
  for _,n in ipairs(notes) do if n.id then changed[n.id]=n end end
  local identical=#notes==#source.notes and (not end_ppq or end_ppq<=source.end_ppq)
  for _,old in ipairs(source.notes) do
    local n=changed[old.id]
    if not n then identical=false; break end
    for _,k in ipairs({'s','e','pitch','vel','channel','selected','muted'}) do if n[k]~=old[k] then identical=false end end
  end
  if identical then return source.raw end
  local function push(pos,flags,msg,order)
    out[#out+1]={pos=math.floor(pos+0.5),flags=flags,msg=msg,order=order}
  end
  for _,ev in ipairs(source.events) do
    if not ev.note_id then
      local pos=ev.pos
      -- REAPER stores the source end in the final all-notes-off/empty event.
      if ev==source.events[#source.events] and end_ppq and end_ppq>pos and
        (#ev.msg==0 or (#ev.msg==3 and ev.msg:byte(1)&0xF0==0xB0 and ev.msg:byte(2)==123)) then pos=end_ppq end
      push(pos,ev.flags,ev.msg,ev.order)
    else
      local n=changed[ev.note_id]
      if n then
        local is_on=ev.is_on
        local flags=(ev.flags&0xFC)|(n.selected and 1 or 0)|(n.muted and 2 or 0)
        local status=is_on and 0x90 or (ev.msg:byte(1)&0xF0)
        local vel=is_on and n.vel or ev.msg:byte(3)
        push(to_ppq(is_on and n.s or n.e),flags,string.char(status|n.channel,n.pitch,vel),ev.order)
      end
    end
  end
  for i,n in ipairs(notes) do if not n.id then
    local flags=(n.selected and 1 or 0)|(n.muted and 2 or 0)
    push(to_ppq(n.s),flags,string.char(0x90|n.channel,n.pitch,n.vel),#source.events+i*2)
    local release=n.off and n.off.msg:byte(3) or 0
    local off_kind=n.off and (n.off.msg:byte(1)&0xF0) or 0x80
    push(to_ppq(n.e),flags,string.char(off_kind|n.channel,n.pitch,release),#source.events+i*2+1)
  end end
  -- Preserve original same-tick ordering, except note offs before note ons.
  local function rank(ev)
    if #ev.msg<3 then return 1 end
    local status=ev.msg:byte(1)&0xF0
    if status==0x80 or (status==0x90 and ev.msg:byte(3)==0) then return 0 end
    return status==0x90 and 2 or 1
  end
  table.sort(out,function(a,b)
    if a.pos~=b.pos then return a.pos<b.pos end
    if rank(a)~=rank(b) then return rank(a)<rank(b) end
    return a.order<b.order
  end)
  local parts,last={},0
  for _,ev in ipairs(out) do
    local delta=ev.pos-last
    -- A sparse source may span more than a signed 32-bit delta.
    while delta>0x7FFFFFFF do parts[#parts+1]=string.pack('i4Bs4',0x7FFFFFFF,0,''); delta=delta-0x7FFFFFFF end
    parts[#parts+1]=string.pack('i4Bs4',delta,ev.flags,ev.msg); last=ev.pos
  end
  return table.concat(parts)
end
return M
