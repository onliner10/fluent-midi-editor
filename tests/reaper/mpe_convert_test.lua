-- Convert to MPE: a plain chord part gets one channel per sounding note,
-- and the clip stays MPE when read again, before any note has expression.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.close_editor()
T.reset()
local item,take=T.midi_item(0,8,{{60,0,2},{64,0,2},{67,0,2},{72,2,4}},'Pad')
-- A channel bend lane on channel 1 becomes the zone's master bend.
r.MIDI_InsertCC(take,false,false,r.MIDI_GetPPQPosFromProjQN(take,1),0xE0,0,0,80)
r.MIDI_Sort(take); r.Undo_OnStateChange('Test: plain chords')
T.select(item)
r.SetExtState('FluentMIDIEditor','expression','1',true)
local function channels()
  local tk=r.GetActiveTake(item); local out={}
  local _,count=r.MIDI_CountEvts(tk)
  for i=0,count-1 do local _,_,_,s,_,chan,pitch=r.MIDI_GetNote(tk,i); out[pitch]=chan end
  return out
end
return T.steps(T.concat(T.open_steps(),
  function()
    local button=T.control('Convert to MPE'); return T.click_steps(button.cx,button.cy)
  end,
  function()
    local ch=channels()
    T.ok(ch[60]>=1 and ch[64]>=1 and ch[67]>=1,'chord notes left the master channel')
    T.ok(ch[60]~=ch[64] and ch[64]~=ch[67] and ch[60]~=ch[67],'one channel per chord note')
    T.ok(ch[72]>=1 and ch[72]<=15,'member channel for the next note')
    local _,mark=r.GetSetMediaItemTakeInfo_String(r.GetActiveTake(item),'P_EXT:FluentMIDIMPE','',false)
    T.eq(mark,'1','clip marked MPE')
    local _,_,ccs=r.MIDI_CountEvts(r.GetActiveTake(item))
    local _,_,_,_,status,chan=r.MIDI_GetCC(r.GetActiveTake(item),0)
    T.eq(ccs,1); T.eq(status,0xE0); T.eq(chan,0,'the bend lane stays on the master channel')
    local S=T.session(item)
    T.ok(S.clips[1].source.mpe,'read again as MPE')
    T.ok(T.control('semitones##bend_range'),'the editor now shows the MPE controls')
    r.Undo_DoUndo2(0)
    T.eq(channels()[64],0,'one Undo restores the channels')
    return true
  end,
  0.5,
  function()
    T.close_editor(); r.SetExtState('FluentMIDIEditor','expression','0',true)
    print('a plain part converts to MPE')
    return true
  end),60)
