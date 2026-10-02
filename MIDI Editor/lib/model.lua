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
-- Tables with this metatable are immutable and shared by copies. MPE notes
-- carry their expression this way, so per-frame drag copies stay cheap.
M.shared={}
function M.copy(value)
  if type(value)~='table' or getmetatable(value)==M.shared then return value end
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
    if e>s then
      local c=M.copy(n); c.id=nil; c.s=s+b-a; c.e=e+b-a
      if s>n.s or e<n.e then M.trim_expression(c,n,s,e) end
      copies[#copies+1]=c
    end
  end end
  if #copies==0 then return nil end
  for _,n in ipairs(notes) do n.selected=false end
  for _,n in ipairs(copies) do notes[#notes+1]=n end
  return {b,b+b-a}
end
-- MPE gives every sounding note its own channel. Pitch bend, channel pressure
-- and CC74 on that channel are the note's expression, so they belong to the
-- note: they move, copy and disappear with it. Only channels that never play
-- two notes at once own expression; shared channels keep plain CC behaviour.
local DIMENSIONS={'pb','at','tb'}
local NEUTRAL={pb=8192,at=0,tb=64}
local function expression(msg)
  local status=msg:byte(1); if not status then return end
  local kind,channel=status&0xF0,status&15
  if kind==0xE0 and #msg>=3 then return 'pb',channel,msg:byte(2)|(msg:byte(3)<<7)
  elseif kind==0xD0 and #msg>=2 then return 'at',channel,msg:byte(2)
  elseif kind==0xB0 and #msg>=3 and msg:byte(2)==74 then return 'tb',channel,msg:byte(3) end
end
M.expression=expression
local function expression_message(dimension,channel,value)
  if dimension=='pb' then return string.char(0xE0|channel,value&127,value>>7) end
  if dimension=='at' then return string.char(0xD0|channel,value) end
  return string.char(0xB0|channel,74,value)
end
local CURVE=string.char(0xFF,15)..'CCBZ '
local function curve_data(msg) return msg:byte(1)==0xFF and msg:sub(1,7)==CURVE end
local function shared(list) return setmetatable(list,M.shared) end
-- REAPER notation ("NOTE channel pitch attributes") and polyphonic aftertouch
-- name their note by channel and pitch, in any clip.
local function notation(msg)
  if msg:byte(1)~=0xFF or msg:byte(2)~=15 then return end
  local channel,pitch=msg:match('^NOTE (%d+) (%d+)',3)
  if channel then return tonumber(channel),tonumber(pitch) end
end
-- The event itself joins the note's list; dt places it relative to the note.
local function own(n,e,from_ppq)
  e.owner=n.id; e.dt=from_ppq(e.pos)-n.s; n.expr=n.expr or {}
  n.expr[#n.expr+1]=e
end
local function attach_note_data(events,paired,from_ppq)
  local starts,spans={}, {}
  for _,n in ipairs(paired) do
    local key=n.channel*128+n.pitch
    starts[key..':'..n.on.pos]=starts[key..':'..n.on.pos] or n
    spans[key]=spans[key] or {}; table.insert(spans[key],n)
  end
  local previous
  for _,e in ipairs(events) do
    local owner
    if not e.note_id then
      local channel,pitch=notation(e.msg)
      if channel then owner=starts[(channel*128+pitch)..':'..e.pos]
      elseif #e.msg>=3 and e.msg:byte(1)&0xF0==0xA0 then
        for _,n in ipairs(spans[(e.msg:byte(1)&15)*128+e.msg:byte(2)] or {}) do
          if e.pos>=n.on.pos and e.pos<=n.off.pos then owner=n; break end
        end
      elseif previous and curve_data(e.msg) then owner=previous end
    end
    if owner then own(owner,e,from_ppq) end
    previous=owner and not curve_data(e.msg) and owner or nil
  end
end
-- Events between two notes on a channel set up the next note (MPE sends the
-- starting bend, pressure and timbre just before note-on). Events after the
-- last note are its release tail. Returns nil for a clip that is not MPE,
-- otherwise the set of its shared (chord-playing) channels. known: the clip
-- was MPE when last written, so one voice left after deleting others stays MPE.
local function attach_expression(events,notes,paired,from_ppq,known)
  local channels={}
  for _,n in ipairs(paired) do
    channels[n.channel]=channels[n.channel] or {}; table.insert(channels[n.channel],n)
  end
  -- A channel with its own program is an instrument part (a GM file), not an
  -- MPE voice; MPE controllers send no program changes on member channels.
  local parts={}
  for _,e in ipairs(events) do if #e.msg==2 and e.msg:byte(1)&0xF0==0xC0 then parts[e.msg:byte(1)&15]=true end end
  local owning,shared_channels={}, {}
  for channel,list in pairs(channels) do
    table.sort(list,function(a,b) return a.on.pos<b.on.pos end)
    local mono=not parts[channel]
    for i=2,#list do if list[i].on.pos<list[i-1].off.pos then mono=false end end
    if mono then owning[channel]=list else shared_channels[channel]=true end
  end
  -- A modulation lane written for CC74 on a channel (its header is a text
  -- event, see modulation.lua) is the lane's timbre, not the notes'.
  local lanes={}
  for _,e in ipairs(events) do
    local channel=e.msg:match('^\255\1LMOD1|L|(%d+)|74|') if channel then lanes[tonumber(channel)]=true end
  end
  -- One parse per event: dimension, channel and value of each expression event.
  local parsed,changes,expressive,found={}, {}, {}, 0
  for i,e in ipairs(events) do
    local dimension,channel,value=expression(e.msg)
    if dimension=='tb' and lanes[channel] then dimension=nil end
    if dimension and owning[channel] then
      parsed[i]=channel
      changes[channel]=changes[channel] or {}; table.insert(changes[channel],{dimension,value,e.pos})
      if not expressive[channel] then expressive[channel]=true; found=found+1 end
    end
  end
  -- MPE spreads notes over member channels. A single channel with bend is an
  -- ordinary part, even when it plays one note at a time.
  if found<(known and 1 or 2) then return nil end
  local current,ended,pending,last,last_channel={}, {}, {}, nil, nil
  local function own_expression(n,e) own(n,e,from_ppq) end
  for i,e in ipairs(events) do
    local channel=parsed[i]
    local n=e.note_id and notes[e.note_id]
    if n and owning[n.channel] then
      if e.is_on then
        current[n.channel]=n
        for _,waiting in ipairs(pending[n.channel] or {}) do own_expression(n,waiting) end
        pending[n.channel]=nil
      else ended[n]=true end
      last=nil
    elseif channel then
      local sounding=current[channel]
      if sounding and not ended[sounding] then own_expression(sounding,e)
      else pending[channel]=pending[channel] or {}; table.insert(pending[channel],e) end
      last,last_channel=e,channel
    elseif last and curve_data(e.msg) then
      -- REAPER keeps a CC's curve shape in the event right after it.
      if last.owner then own_expression(notes[last.owner],e) else table.insert(pending[last_channel],e) end
      last=nil
    else last=nil end
  end
  for channel,list in pairs(pending) do for _,e in ipairs(list) do own_expression(current[channel],e) end end
  -- The state each note starts with: every event at or before its note-on,
  -- since encoding places same-tick controllers before note-ons.
  for channel,list in pairs(owning) do
    local state,index,steps={}, 1, changes[channel] or {}
    for _,n in ipairs(list) do
      while steps[index] and steps[index][3]<=n.on.pos do state[steps[index][1]]=steps[index][2]; index=index+1 end
      n.initial=shared({pb=state.pb,at=state.at,tb=state.tb})
    end
  end
  return shared_channels
end
-- A copy that keeps only part of a note keeps only that part's expression,
-- starting from the state its original had at the cut.
function M.trim_expression(copy,original,s,e)
  if not original.expr then return end
  local from,to=s-original.s,e-original.s
  local state={}; for _,d in ipairs(DIMENSIONS) do state[d]=original.initial and original.initial[d] end
  local kept,previous={},nil
  for _,x in ipairs(original.expr) do
    local dimension,_,value=expression(x.msg)
    local inside,dt=x.dt>from and x.dt<=to,x.dt-from
    if dimension then previous=inside; if x.dt<=from then state[dimension]=value end
    elseif notation(x.msg) then inside,dt=true,0
    elseif curve_data(x.msg) then inside=previous
    else inside=x.dt>=from and x.dt<=to end
    if inside then kept[#kept+1]={dt=dt,pos=x.pos,flags=x.flags,msg=x.msg,order=x.order} end
  end
  copy.expr=shared(kept)
  if original.initial then copy.initial=shared({pb=state.pb,at=state.at,tb=state.tb}) end
end
-- MIDI cannot hold two sounding notes of one pitch on one channel. As in
-- Ableton: an edited note over the start of another note replaces it; over its
-- end, it shortens it. Two edited notes: the earlier ends where the later
-- starts. Overlaps no edit touched stay as they are. originals: unedited notes
-- by id. Returns the notes that remain; a shortened note is a copy, so the
-- notes passed in stay as they were.
function M.resolve_overlaps(notes,originals)
  local ends={}
  local function ending(n) return ends[n] or n.e end
  local function edited(n)
    local o=n.id and originals[n.id]
    return not o or o.s~=n.s or o.e~=ending(n) or o.pitch~=n.pitch or o.channel~=n.channel
  end
  local groups={}
  for _,n in ipairs(notes) do
    local key=n.channel*128+n.pitch; groups[key]=groups[key] or {}; table.insert(groups[key],n)
  end
  local removed={}
  for _,list in pairs(groups) do
    table.sort(list,function(a,b) if a.s~=b.s then return a.s<b.s end; return edited(a) and not edited(b) end)
    for i,later in ipairs(list) do
      for j=1,i-1 do local earlier=list[j]
        if not removed[earlier] and not removed[later] and ending(earlier)>later.s+1e-9 and (edited(earlier) or edited(later)) then
          if edited(earlier) and not edited(later) then removed[later]=true
          else ends[earlier]=later.s; if later.s-earlier.s<1e-9 then removed[earlier]=true end end
        end
      end
    end
  end
  local out={}
  for _,n in ipairs(notes) do if not removed[n] then
    if ends[n] then local c={}; for k,v in pairs(n) do c[k]=v end; c.e=ends[n]; n=c end
    out[#out+1]=n
  end end
  return out
end
-- A new or moved note that lands on a channel another note is using gets the
-- least recently used free channel of the zone, so expression stays per note.
function M.allocate_channels(notes,originals,shared_channels)
  shared_channels=shared_channels or {}
  local by_channel,used={}, {}
  for c=0,15 do by_channel[c]={} end
  for _,n in ipairs(notes) do table.insert(by_channel[n.channel],n); used[n.channel]=true end
  local lo,hi=1,15
  if used[0] then if used[15] then lo,hi=0,15 else lo,hi=0,14 end end
  local dirty={}
  for _,n in ipairs(notes) do
    local old=n.id and originals[n.id]
    if (not old or old.s~=n.s or old.e~=n.e or old.channel~=n.channel) and not shared_channels[n.channel] then dirty[#dirty+1]=n end
  end
  table.sort(dirty,function(a,b) return a.s<b.s end)
  local function clash(n,channel)
    for _,o in ipairs(by_channel[channel]) do
      if o~=n and o.s<n.e-1e-9 and n.s<o.e-1e-9 then return true end
    end
  end
  for _,n in ipairs(dirty) do if clash(n,n.channel) then
    local best,free_since
    for channel=lo,hi do if not shared_channels[channel] and not clash(n,channel) then
      -- Unused channels first; then the one silent for longest.
      local since=#by_channel[channel]>0 and -1e300 or -math.huge
      for _,o in ipairs(by_channel[channel]) do if o.e<=n.s+1e-9 then since=math.max(since,o.e) end end
      if not best or since<free_since then best,free_since=channel,since end
    end end
    if best then
      for i,o in ipairs(by_channel[n.channel]) do if o==n then table.remove(by_channel[n.channel],i); break end end
      n.channel=best; table.insert(by_channel[best],n)
    end
  end end
end
-- After notes moved, a channel's controller state at each note-on must still
-- be what that note started with, and one note's expression must not reach
-- another note that now plays on its channel.
local function settle(out)
  local result,state,current,sounding,on_pos,dropped={}, {}, {}, {}, {}, false
  for _,ev in ipairs(out) do if ev.note and ev.is_on then on_pos[ev.note]=ev.pos end end
  for c=0,15 do state[c]={} end
  for _,ev in ipairs(out) do
    local dimension,channel,value=expression(ev.msg)
    if ev.note then
      local n=ev.note
      if ev.is_on then
        if ev.wants then
          for _,d in ipairs(DIMENSIONS) do
            local v=ev.wants[d]
            if v==nil and state[n.channel][d]~=nil then v=NEUTRAL[d] end
            if v~=nil and state[n.channel][d]~=v then
              result[#result+1]={pos=ev.pos,flags=0,msg=expression_message(d,n.channel,v)}
              state[n.channel][d]=v
            end
          end
        end
        current[n.channel]=n; sounding[n]=true
      else sounding[n]=nil end
      result[#result+1]=ev; dropped=false
    elseif dimension then
      local other=current[channel]
      dropped=ev.owner and other and other~=ev.owner and (sounding[other] or on_pos[other]>on_pos[ev.owner]) or false
      if not dropped then result[#result+1]=ev; state[channel][dimension]=value end
    elseif curve_data(ev.msg) and dropped then
    else result[#result+1]=ev; dropped=false end
  end
  return result
end
-- Keep opaque events (CC, pitch bend, text, sysex, notation) and note-off velocity.
-- IDs refer to original on/off events, so sorting never changes edit identity.
function M.decode(raw,from_ppq,known_mpe)
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
  attach_note_data(events,paired,from_ppq)
  -- Channels that play chords in an MPE clip (a master channel) stay shared.
  local shared_channels=attach_expression(events,notes,paired,from_ppq,known_mpe)
  for _,n in ipairs(paired) do if n.expr then
    local sorted=true
    for i=2,#n.expr do if n.expr[i].order<n.expr[i-1].order then sorted=false; break end end
    if not sorted then table.sort(n.expr,function(a,b) return a.order<b.order end) end
    shared(n.expr)
  end end
  return {events=events,notes=paired,end_ppq=pos,raw=raw,mpe=shared_channels~=nil,shared=shared_channels}
end
-- A message that belongs to note n, retargeted to its channel and pitch.
local function retarget(msg,n)
  local status=msg:byte(1)
  if status and status>=0x80 and status<0xF0 then
    if status&0xF0==0xA0 then return string.char((status&0xF0)|n.channel,n.pitch)..msg:sub(3) end
    return string.char((status&0xF0)|n.channel)..msg:sub(2)
  end
  if notation(msg) then
    return (msg:gsub('^(..NOTE )%d+ %d+',function(prefix) return prefix..n.channel..' '..n.pitch end,1))
  end
  return msg
end
function M.encode(source,notes,to_ppq,end_ppq)
  to_ppq=to_ppq or function(x) return x end
  local changed,out,originals={}, {}, {}
  for _,old in ipairs(source.notes) do originals[old.id]=old end
  local mpe=source.mpe
  for _,n in ipairs(notes) do if not n.id and n.initial then mpe=true end end
  local shared_channels=source.shared or {}
  if mpe then M.allocate_channels(notes,originals,shared_channels) end
  notes=M.resolve_overlaps(notes,originals)
  -- A note starts from the controller state it had; a new one from neutral.
  local function wants(n)
    if not mpe then return nil end
    if n.initial then return n.initial end
    if not n.id and not shared_channels[n.channel] then return {} end
  end
  for _,n in ipairs(notes) do if n.id then changed[n.id]=n end end
  local identical=#notes==#source.notes and (not end_ppq or end_ppq<=source.end_ppq)
  for _,old in ipairs(source.notes) do
    local n=changed[old.id]
    if not n then identical=false; break end
    for _,k in ipairs({'s','e','pitch','vel','channel','selected','muted'}) do if n[k]~=old[k] then identical=false end end
  end
  if identical then return source.raw end
  local function push(pos,flags,msg,order,extra)
    local ev=extra or {}
    ev.pos,ev.flags,ev.msg,ev.order=math.floor(pos+0.5),flags,msg,order
    out[#out+1]=ev
  end
  local limit=math.max(end_ppq or 0,source.end_ppq)
  for _,ev in ipairs(source.events) do
    if ev.owner then
      -- Emitted with its note below; a deleted note takes it along.
    elseif not ev.note_id then
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
        push(to_ppq(is_on and n.s or n.e),flags,string.char(status|n.channel,n.pitch,vel),ev.order,
          {note=n,is_on=is_on,wants=is_on and wants(n) or nil})
      end
    end
  end
  for i,n in ipairs(notes) do if not n.id then
    local flags=(n.selected and 1 or 0)|(n.muted and 2 or 0)
    push(to_ppq(n.s),flags,string.char(0x90|n.channel,n.pitch,n.vel),#source.events+i*2,
      {note=n,is_on=true,wants=wants(n)})
    local release=n.off and n.off.msg:byte(3) or 0
    local off_kind=n.off and (n.off.msg:byte(1)&0xF0) or 0x80
    push(to_ppq(n.e),flags,string.char(off_kind|n.channel,n.pitch,release),#source.events+i*2+1,{note=n})
  end end
  -- Everything a note owns travels with it. A move shifts both edges by the
  -- same amount; resizing one edge leaves the owned events where they were.
  local extra=#source.events+#notes*2+2
  for _,n in ipairs(notes) do
    local old=n.id and originals[n.id]
    local list=old and old.expr or n.expr
    if list then
      local moved=not old or (math.abs((n.s-old.s)-(n.e-old.e))<1e-9 and n.s~=old.s)
      local same=old and old.channel==n.channel and old.pitch==n.pitch
      for _,x in ipairs(list) do
        local pos=moved and to_ppq(n.s+x.dt) or x.pos
        if pos>=-0.5 and pos<=limit then
          extra=extra+1
          push(pos,x.flags,same and x.msg or retarget(x.msg,n),old and x.order or extra,{owner=n})
        end
      end
    end
  end
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
  if mpe then out=settle(out) end
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
