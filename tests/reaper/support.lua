-- Helpers for tests/reaper/*_test.lua. Those run inside a live REAPER through
-- tools/reaper/reaper.sh, which provides ROOT (the repository) and print().
local r=reaper
local T={lib=ROOT..'/MIDI Editor/lib/',open=ROOT..'/MIDI Editor/Fluent MIDI Editor - Open.lua'}

function T.load(name) return dofile(T.lib..name..'.lua') end
function T.eq(a,b,label)
  if a~=b then error((label or 'values differ')..': '..tostring(a)..' ~= '..tostring(b),2) end
end
function T.ok(value,label) if not value then error(label or 'assertion failed',2) end return value end

-- Empty project and no running editor, so every test starts from the same state.
function T.reset()
  r.SetExtState('FluentMIDIEditor','instance','',false)
  for _,k in ipairs({'heartbeat','error','focus','target'}) do r.DeleteExtState('FluentMIDIEditor',k,false) end
  r.SelectAllMediaItems(0,false)
  for i=r.CountTracks(0)-1,0,-1 do r.DeleteTrack(r.GetTrack(0,i)) end
  r.SetEditCurPos(0,false,false)
  r.Undo_OnStateChange('Test: reset')
end

-- A MIDI item on a new track. notes: {{pitch,start_qn,end_qn},...} relative to the item.
function T.midi_item(start_qn,length_qn,notes,name)
  local index=r.CountTracks(0); r.InsertTrackAtIndex(index,true)
  local track=r.GetTrack(0,index)
  if name then r.GetSetMediaTrackInfo_String(track,'P_NAME',name,true) end
  local item=r.CreateNewMIDIItemInProj(track,r.TimeMap2_QNToTime(0,start_qn),
    r.TimeMap2_QNToTime(0,start_qn+length_qn),false)
  local take=r.GetActiveTake(item)
  for _,n in ipairs(notes or {}) do
    r.MIDI_InsertNote(take,false,false,r.MIDI_GetPPQPosFromProjQN(take,start_qn+n[2]),
      r.MIDI_GetPPQPosFromProjQN(take,start_qn+n[3]),0,n[1],100,true)
  end
  r.MIDI_Sort(take)
  -- An undo point per setup step, so a test's Undo stops at its own setup.
  r.Undo_OnStateChange('Test: add clip')
  return item,take,track
end

function T.select(...)
  r.SelectAllMediaItems(0,false)
  for _,item in ipairs({...}) do r.SetMediaItemSelected(item,true) end
  r.UpdateArrange()
end

-- Notes of a take as {pitch,start_qn,end_qn} sorted by start then pitch.
function T.notes(take)
  local out={}
  local _,count=r.MIDI_CountEvts(take)
  for i=0,count-1 do
    local _,_,_,s,e,_,pitch=r.MIDI_GetNote(take,i)
    out[#out+1]={pitch,r.MIDI_GetProjQNFromPPQPos(take,s),r.MIDI_GetProjQNFromPPQPos(take,e)}
  end
  table.sort(out,function(a,b) if a[2]~=b[2] then return a[2]<b[2] end return a[1]<b[1] end)
  return out
end

-- Run the Open action as REAPER would (its own script instance, deferred loop).
function T.open_editor()
  local id=r.AddRemoveReaScript(true,0,T.open,true)
  T.ok(id~=0,'could not register the Open action')
  r.Main_OnCommand(id,0)
end
function T.editor_running()
  local stamp=tonumber(r.GetExtState('FluentMIDIEditor','heartbeat'))
  return stamp and r.time_precise()-stamp<1
end
function T.close_editor() r.SetExtState('FluentMIDIEditor','instance','',false) end

-- Return from a test to keep it running across defer cycles: check() is called
-- each cycle until it returns true (pass) or the timeout (seconds) runs out.
function T.wait(check,timeout)
  local deadline=r.time_precise()+(timeout or 10)
  return function()
    if check() then return true end
    if r.time_precise()>deadline then error('condition not met within '..(timeout or 10)..'s',0) end
  end
end

return T
