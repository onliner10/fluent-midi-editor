-- With MPE editing on, a selected note's flat pitch line runs through its
-- middle. Note gestures still win where they belong: the edge resizes,
-- Alt+drag sets velocity, Ctrl+drag copies the note. None adds a bend.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.close_editor()
T.reset()
local item,take=T.midi_item(0,8,{},'MPE')
local function ppq(qn) return math.floor(r.MIDI_GetPPQPosFromProjQN(take,qn)+.5) end
local function pb(ch,v) return string.char(0xE0|ch,v&127,v>>7) end
local list={
  {0,pb(1,8192)},{0,string.char(0x91,60,100)},{ppq(2),string.char(0x81,60,0)},
  {ppq(2),pb(2,8192)},{ppq(2),string.char(0x92,64,70)},{ppq(4),string.char(0x82,64,0)},{ppq(8),string.char(0xB0,123,0)}}
local parts,last={},0
for _,e in ipairs(list) do parts[#parts+1]=string.pack('i4Bs4',e[1]-last,0,e[2]); last=e[1] end
T.ok(r.MIDI_SetAllEvts(take,table.concat(parts)),'write MPE take')
r.MIDI_Sort(take); r.Undo_OnStateChange('Test: MPE take')
T.select(item)
r.SetExtState('FluentMIDIEditor','expression','1',true)
local function bends()
  local tk=r.GetActiveTake(item); local n=0
  local _,_,ccs=r.MIDI_CountEvts(tk)
  for i=0,ccs-1 do local _,_,_,_,chanmsg=r.MIDI_GetCC(tk,i); if chanmsg==0xE0 then n=n+1 end end
  return n
end
local function c3_note()
  local tk=r.GetActiveTake(item); local out={}
  local _,count=r.MIDI_CountEvts(tk)
  for i=0,count-1 do local _,_,_,s,e,_,pitch,vel=r.MIDI_GetNote(tk,i)
    if pitch==60 then out[#out+1]={len=r.MIDI_GetProjQNFromPPQPos(tk,e)-r.MIDI_GetProjQNFromPPQPos(tk,s),vel=vel} end end
  return out
end
local c3,cy,start_bends
return T.steps(T.concat(T.open_steps(),
  function()
    c3=T.find(T.note_color(100)); T.ok(c3,'C3 not drawn'); cy=(c3[2]+c3[4])//2
    start_bends=bends()
    return T.click_steps(c3.cx,c3[2]+2)
  end,
  -- The right edge at the height of the pitch line resizes the note.
  function() return T.drag_steps(c3[3]-1,cy,c3[3]+60,cy) end,
  function()
    local n=c3_note(); T.eq(#n,1); T.ok(n[1].len>2.05,'edge drag lengthened C3: '..n[1].len)
    T.eq(bends(),start_bends,'no bend added by the edge drag')
    return true
  end,
  -- Alt+drag on the line sets velocity.
  function()
    return T.concat({function() T.keydown('alt'); return true end,0.2},
      T.drag_steps(c3[1]+30,cy,c3[1]+30,cy-40),{function() T.keyup('alt'); return true end,0.4})
  end,
  function()
    local n=c3_note(); T.ok(n[1].vel>100,'Alt+drag raised velocity: '..n[1].vel)
    T.eq(bends(),start_bends,'no bend added by Alt+drag')
    return true
  end,
  -- Ctrl+drag on the flat line copies the note.
  function()
    return T.concat({function() T.keydown('ctrl'); return true end,0.2},
      T.drag_steps(c3[1]+30,cy,c3[1]+30,cy-60),{function() T.keyup('ctrl'); return true end,0.4})
  end,
  function()
    local tk=r.GetActiveTake(item); local _,count=r.MIDI_CountEvts(tk)
    T.eq(count,3,'Ctrl+drag copied C3')
    return true
  end,
  0.3,
  function()
    T.close_editor(); r.SetExtState('FluentMIDIEditor','expression','0',true)
    print('note gestures keep working with MPE editing on')
    return true
  end),60)
