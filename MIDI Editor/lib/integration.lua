local I={section='FluentMIDIEditor',context='MM_CTX_ITEM_DBLCLK'}
-- root: the folder holding the action scripts, wherever ReaPack installed them.
function I.paths(root)
  return root..'Fluent MIDI Editor - Open.lua',root..'Fluent MIDI Editor - Restore default editor.lua'
end
function I.install(r,root)
  local path,restore=I.paths(root)
  local id=r.AddRemoveReaScript(true,0,path,true)
  assert(id~=0,'Could not register the editor')
  r.AddRemoveReaScript(true,0,restore,true)
  local command=r.ReverseNamedCommandLookup(id)
  if command:sub(1,1)~='_' then command='_'..command end
  local current=r.GetMouseModifier(I.context,0)
  local previous=r.GetExtState(I.section,'previous_double_click')
  if previous=='' and current~=command..' c' and current~=command then
    r.SetExtState(I.section,'previous_double_click',current,true)
  end
  r.SetMouseModifier(I.context,0,command..' c')
  r.SetExtState(I.section,'double_click_command',command..' c',true)
  return id
end
function I.restore(r)
  local before=r.GetExtState(I.section,'previous_double_click')
  local ours=r.GetExtState(I.section,'double_click_command')
  local current=r.GetMouseModifier(I.context,0)
  if ours=='' then return false,'No saved double-click override.' end
  -- Do not overwrite a later preference change made by the user.
  if current~=ours and current~=ours:gsub(' c$','') then
    return false,'The double-click action was already changed in REAPER preferences.'
  end
  r.SetMouseModifier(I.context,0,before~='' and before or '-1')
  r.DeleteExtState(I.section,'previous_double_click',true)
  r.DeleteExtState(I.section,'double_click_command',true)
  return true,'Previous double-click action restored.'
end
return I
