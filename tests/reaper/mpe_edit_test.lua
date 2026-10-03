-- MPE editing with the mouse, as in Ableton's Note Expression view: drag a
-- selected note's pitch line to bend it, drag a pressure point in the lane.
-- REAPER then holds the new per-note expression on the note's channel.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.close_editor()
T.reset()
local item,take=T.midi_item(0,8,{},'MPE')
local function ppq(qn) return math.floor(r.MIDI_GetPPQPosFromProjQN(take,qn)+.5) end
local function pb(ch,v) return string.char(0xE0|ch,v&127,v>>7) end
-- C3 on channel 2 (velocity 100) with a pressure step; E3 on channel 3 (velocity 70).
local list={
  {0,pb(1,8192)},{0,string.char(0xD1,0)},{0,string.char(0x91,60,100)},
  {ppq(1),string.char(0xD1,90)},{ppq(2),string.char(0x81,60,0)},
  {ppq(2),pb(2,8192)},{ppq(2),string.char(0xD2,20)},{ppq(2),string.char(0x92,64,70)},
  {ppq(4),string.char(0x82,64,0)},{ppq(8),string.char(0xB0,123,0)}}
local parts,last={},0
for _,e in ipairs(list) do parts[#parts+1]=string.pack('i4Bs4',e[1]-last,0,e[2]); last=e[1] end
T.ok(r.MIDI_SetAllEvts(take,table.concat(parts)),'write MPE take')
r.MIDI_Sort(take); r.Undo_OnStateChange('Test: MPE take')
T.select(item)
r.SetExtState('FluentMIDIEditor','expression','1',true)

-- Pitch bend or pressure events of a channel as {qn,value}.
local function events(channel,kind)
  local tk=r.GetActiveTake(item); local out={}
  local _,_,ccs=r.MIDI_CountEvts(tk)
  for i=0,ccs-1 do
    local _,_,_,pos,chanmsg,chan,m1,m2=r.MIDI_GetCC(tk,i)
    if chan==channel and chanmsg==kind then
      out[#out+1]={r.MIDI_GetProjQNFromPPQPos(tk,pos),kind==0xE0 and (m1|(m2<<7)) or m1}
    end
  end
  return out
end
local function value_at(channel,kind,qn)
  local v; for _,e in ipairs(events(channel,kind)) do if e[1]<=qn+1e-6 then v=e[2] end end
  return v
end

local c3,lane
return T.steps(T.concat(T.open_steps(),
  function()
    c3=T.find(T.note_color(100)); T.ok(c3,'C3 not drawn')
    T.ok(T.find(T.note_color(70)),'E3 not drawn')
    return true
  end,
  -- Select C3, then drag its pitch line from the middle of the note two rows up.
  function() return T.click_steps(c3.cx,c3[2]+2) end,
  function()
    local rowh=c3[4]-c3[2]+3
    local cy=(c3[2]+c3[4])//2
    return T.drag_steps(c3.cx,cy,c3.cx+2,cy-2*rowh)
  end,
  function()
    local bend=events(1,0xE0)
    T.ok(#bend>10,'a ramp of pitch bend was written: '..#bend)
    T.eq(value_at(1,0xE0,0),8192,'C3 starts in tune')
    local top=value_at(1,0xE0,1.95)
    -- Two rows are two semitones at the default 48-semitone MPE range.
    T.ok(math.abs(top-(8192+2*8192/48))<40,'bent two semitones up: '..tostring(top))
    T.eq(#events(2,0xE0),1,'E3 keeps its own bend')
    T.eq(value_at(1,0xD0,1.5),90,'pressure untouched')
    return true
  end,
  -- Pressure lane: drag C3's starting pressure point halfway up.
  function() local tab=T.control('lane Pressure'); return T.click_steps(tab.cx,tab.cy) end,
  function()
    lane=T.control('lane')
    local x,y=c3[1]-1,lane[4]-4
    return T.drag_steps(x,y,x,y-(lane[4]-lane[2]-10)//2)
  end,
  function()
    local start=value_at(1,0xD0,0)
    T.ok(start>=55 and start<=72,'starting pressure raised to about 64: '..tostring(start))
    T.eq(value_at(1,0xD0,1.5),90,'the step to 90 stays')
    T.eq(value_at(2,0xD0,2),20,'E3 pressure untouched')
    T.ok(math.abs(value_at(1,0xE0,1.95)-(8192+2*8192/48))<40,'pitch bend kept')
    r.Undo_DoUndo2(0)
    T.eq(value_at(1,0xD0,0),0,'one Undo restores the pressure')
    return true
  end,
  0.5,
  function()
    T.close_editor(); r.SetExtState('FluentMIDIEditor','expression','0',true)
    print('MPE pitch and pressure edited with the mouse')
    return true
  end),60)
