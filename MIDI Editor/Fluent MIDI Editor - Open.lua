-- @description Fluent MIDI Editor
-- @version 0.9.0
-- @author onliner10
-- @about
--   Finally, a MIDI editor for REAPER that feels good. A dockable piano roll
--   that edits clips on several tracks at once, with phrase repeats, clip-owned
--   CC curves and native Undo. Requires ReaImGui (ReaPack). SWS is optional.
-- @links
--   Repository https://github.com/onliner10/fluent-midi-editor
-- @provides
--   [main] Fluent MIDI Editor - Set as default editor.lua
--   [main] Fluent MIDI Editor - Restore default editor.lua
--   lib/*.lua
local root=debug.getinfo(1,'S').source:sub(2):match('^(.*[\\/])')
local r=reaper
local item=r.GetSelectedMediaItem(0,0)
-- Mouse context takes priority when invoked by the media-item double click.
if r.BR_GetMouseCursorContext then
  local window,segment=r.BR_GetMouseCursorContext()
  if window=='arrange' and segment=='track' then
    local under=r.BR_GetMouseCursorContext_Item(); if under then item=under end
  end
end
local take=item and r.GetActiveTake(item)
if take and not r.TakeIsMIDI(take) then
  -- Preserve REAPER's usual source-properties behavior for audio items.
  r.Main_OnCommand(40009,0)
  return
end
local stamp=tonumber(r.GetExtState('FluentMIDIEditor','heartbeat')) or 0
if r.time_precise()-stamp<1 then
  r.SetExtState('FluentMIDIEditor','focus','1',false)
  if item then r.SetExtState('FluentMIDIEditor','target',r.BR_GetMediaItemGUID and r.BR_GetMediaItemGUID(item) or '',false) end
  return
end
if not r.ImGui_GetBuiltinPath then
  r.MB('Install ReaImGui from Extensions > ReaPack > Browse packages, then run the editor again.',
    'Fluent MIDI Editor needs ReaImGui',0)
  return
end
dofile(root..'lib/editor.lua').run(r,item,root..'lib/')
