-- The Open action starts the editor on the selected clip and keeps drawing.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item=T.midi_item(0,8,{{60,0,1},{62,1,2},{64,2,3},{67,3,4}},'Keys')
T.select(item)
T.open_editor()
local first
return T.wait(function()
  local err=r.GetExtState('FluentMIDIEditor','error')
  if err~='' then error('editor failed: '..err,0) end
  if not T.editor_running() then return end
  -- The heartbeat is written every 0.25 s from the deferred loop; seeing it
  -- advance means frames keep drawing without errors.
  local stamp=tonumber(r.GetExtState('FluentMIDIEditor','heartbeat'))
  first=first or stamp
  if stamp-first<0.5 then return end
  T.close_editor()
  print('editor running on 1 clip')
  return true
end,20)
