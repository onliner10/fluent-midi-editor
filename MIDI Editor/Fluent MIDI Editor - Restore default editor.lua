-- @noindex
local root=debug.getinfo(1,'S').source:sub(2):match('^(.*[\\/])')
local _,message=dofile(root..'lib/integration.lua').restore(reaper)
reaper.MB(message,'Fluent MIDI Editor',0)
