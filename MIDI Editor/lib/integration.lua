local I={section='FluentMIDIEditor',context='MM_CTX_ITEM_DBLCLK'}
-- REAPER takes a script action by its numeric command ID and reports it back as
-- its named ID ('_RS...') with no suffix. It does not understand '_RS... c' and
-- stores "No action" ('0') instead, which is what 0.9.0 left behind.
local NO_ACTION={['0']=true,['0 m']=true,['0 c']=true}
local function same(a,b) return (a:gsub(' c$',''))==(b:gsub(' c$','')) end
-- root: the folder holding the action scripts, wherever ReaPack installed them.
function I.paths(root)
  return root..'Fluent MIDI Editor - Open.lua',root..'Fluent MIDI Editor - Restore default editor.lua'
end
-- Returns the command ID, or nil and a message when REAPER rejects the change.
function I.install(r,root)
  local path,restore=I.paths(root)
  local id=r.AddRemoveReaScript(true,0,path,true)
  if id==0 then return nil,'Could not register the editor action.' end
  r.AddRemoveReaScript(true,0,restore,true)
  local command=r.ReverseNamedCommandLookup(id)
  if command:sub(1,1)~='_' then command='_'..command end
  local current=r.GetMouseModifier(I.context,0)
  if r.GetExtState(I.section,'previous_double_click')=='' and not same(current,command) and not NO_ACTION[current] then
    r.SetExtState(I.section,'previous_double_click',current,true)
  end
  r.SetMouseModifier(I.context,0,tostring(id))
  local now=r.GetMouseModifier(I.context,0)
  if not same(now,command) then
    r.SetMouseModifier(I.context,0,current)
    return nil,'REAPER did not accept the double-click action (got "'..now..'").'
  end
  r.SetExtState(I.section,'double_click_command',command,true)
  return id
end
function I.restore(r)
  local before=r.GetExtState(I.section,'previous_double_click')
  local ours=r.GetExtState(I.section,'double_click_command')
  local current=r.GetMouseModifier(I.context,0)
  if ours=='' then return false,'No saved double-click override.' end
  -- Do not overwrite a later preference change made by the user.
  if not same(current,ours) and not NO_ACTION[current] then
    return false,'The double-click action was already changed in REAPER preferences.'
  end
  r.SetMouseModifier(I.context,0,before~='' and before or '-1')
  r.DeleteExtState(I.section,'previous_double_click',true)
  r.DeleteExtState(I.section,'double_click_command',true)
  return true,'Previous double-click action restored.'
end
I.links={discord='https://discord.gg/F6TJ6SDHcV',issues='https://github.com/onliner10/fluent-midi-editor/issues'}
-- Opens a web page in the default browser: SWS when installed, else the OS opener.
function I.open_url(r,url)
  if r.CF_ShellExecute then r.CF_ShellExecute(url) return end
  local os_name=r.GetOS()
  if os_name:match('^Win') then os.execute('start "" "'..url..'"')
  elseif os_name:match('^OSX') or os_name:match('^macOS') then os.execute('open "'..url..'"')
  else os.execute('xdg-open "'..url..'" &') end
end
return I
