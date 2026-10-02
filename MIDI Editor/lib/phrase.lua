-- Turn audible loop occurrences into one editable phrase. No render/Glue action
-- and no selection changes: only the active take's MIDI source is replaced.
local P={}
-- An error for the user: transactions show its message without a traceback.
local function refuse(message) error({message=message},0) end
local function terminal(event)
  return #event.msg==0 or (#event.msg==3 and event.msg:byte(1)&0xF0==0xB0 and event.msg:byte(2)==123)
end
local function pack(events,ending)
  table.sort(events,function(a,b) return a.pos==b.pos and a.order<b.order or a.pos<b.pos end)
  local parts,last={},0
  for _,event in ipairs(events) do
    local pos=math.floor(event.pos+.5)
    parts[#parts+1]=string.pack('i4Bs4',pos-last,event.flags,event.msg); last=pos
  end
  parts[#parts+1]=string.pack('i4Bs4',math.floor(ending+.5)-last,0,string.char(0xB0,123,0))
  return table.concat(parts)
end
-- Collect repetitions in PPQ, clipped to audible cycle and requested bounds.
local function occurrences(source,a,z,start,finish)
  local events={}; local period=z-a
  assert(period>0,'Invalid MIDI phrase length')
  local function add(pos,event)
    events[#events+1]={pos=pos,flags=event.flags,msg=event.msg,order=#events+1}
  end
  local first=math.floor((start-a)/period+1e-8)
  local last=math.ceil((finish-a)/period-1e-8)-1
  for cycle=first,last do
    local shift=cycle*period
    local lo,hi=math.max(start,a+shift),math.min(finish,z+shift)
    for _,note in ipairs(source.notes) do
      local s,e=math.max(lo,note.on.pos+shift),math.min(hi,note.off.pos+shift)
      if e>s and note.on.pos<z and note.off.pos>a then add(s,note.on); add(e,note.off) end
    end
    for i,event in ipairs(source.events) do
      local pos=event.pos+shift
      if not event.note_id and not (i==#source.events and terminal(event))
        and event.pos>=a and event.pos<z and pos>=lo and pos<hi then add(pos,event) end
    end
  end
  return events
end
function P.materialize(source,start,finish)
  local events=occurrences(source,0,source.end_ppq,start,finish)
  for _,event in ipairs(events) do event.pos=event.pos-start end
  return pack(events,finish-start)
end
-- Copies of [a,z) from a up to finish, like Ctrl+D on the whole clip. The
-- rest of the source stays; whatever was hidden in [z,finish) is replaced.
function P.duplicate(source,a,z,finish)
  local events,notes={},{}
  for _,note in ipairs(source.notes) do notes[note.id]=note end
  for i,event in ipairs(source.events) do
    local note=event.note_id and notes[event.note_id]
    local outside
    if note then outside=note.off.pos<=a or note.on.pos>=finish
    else outside=event.pos<a or event.pos>=finish end
    if outside and not (i==#source.events and terminal(event)) then
      events[#events+1]={pos=event.pos,flags=event.flags,msg=event.msg,order=#events+1}
    end
  end
  for _,event in ipairs(occurrences(source,a,z,a,finish)) do
    event.order=#events+1; events[#events+1]=event
  end
  return pack(events,math.max(finish,source.end_ppq))
end
-- The same source ending later: the part that grows is silent.
function P.lengthen(source,ending)
  return P.duplicate(source,ending,ending+1,ending)
end
function P.detach(r,b)
  local ok,chunk=r.GetItemStateChunk(b.item,'',false); assert(ok,'Could not back up the phrase')
  local _,takeid=r.GetSetMediaItemTakeInfo_String(b.take,'GUID','',false)
  local depth,active,count=0,false,0
  local pool=r.genGuid(); local lines={}
  for original in chunk:gmatch('[^\r\n]+') do
    local line=original
    if depth==1 and line:match('^GUID ') then active=line:match('%b{}')==takeid end
    if active and depth==1 and line=='<SOURCE MIDIPOOL' then line='<SOURCE MIDI' end
    if active and depth==2 and line:match('^POOLEDEVTS ') then line='POOLEDEVTS '..pool; count=count+1 end
    lines[#lines+1]=line
    if line:sub(1,1)=='<' then depth=depth+1 elseif line=='>' then depth=depth-1 end
  end
  assert(count==1,'Could not separate the active MIDI take source')
  assert(r.SetItemStateChunk(b.item,table.concat(lines,'\n')..'\n',false),'Could not prepare the new phrase')
  b.take=r.GetActiveTake(b.item)
end
function P.resize(r,b,bars,L)
  local target=L.end_qn(r,b,bars)
  local start=r.MIDI_GetPPQPosFromProjQN(b.take,b.item_start)
  local finish=r.MIDI_GetPPQPosFromProjQN(b.take,target)
  if finish-start<1 then refuse('The phrase must be at least one MIDI tick long.') end
  if r.GetMediaItemInfo_Value(b.item,'C_LOCK')&1~=0 then refuse('The clip is locked.') end
  local raw
  if b.looped and not b.single then
    -- Retain a full original cycle when shortening, so hidden notes can return.
    raw=P.materialize(b.source,start,math.max(finish,start+b.source.end_ppq))
    P.detach(r,b)
    assert(r.SetMediaItemTakeInfo_Value(b.take,'D_STARTOFFS',0),'Could not set the phrase start')
    assert(r.SetMediaItemInfo_Value(b.item,'B_LOOPSRC',0),'Could not set the phrase')
  else
    -- What plays past the phrase end is its repeats, so lengthening pulls in
    -- copies of the phrase, not notes hidden in the source by a shortening.
    local ending=r.MIDI_GetPPQPosFromProjQN(b.take,b.item_end)
    if finish>ending+1e-7 then raw=P.duplicate(b.source,start,ending,finish) end
  end
  if raw then assert(r.MIDI_SetAllEvts(b.take,raw),'Could not write the phrase'); r.MIDI_Sort(b.take) end
  assert(r.SetMediaItemInfo_Value(b.item,'D_LENGTH',r.TimeMap2_QNToTime(b.project,target)-b.position),'Could not set the phrase length')
  r.UpdateItemInProject(b.item)
  b:read()
end
return P
