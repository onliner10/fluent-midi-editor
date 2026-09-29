-- @noindex
local root=debug.getinfo(1,'S').source:sub(2):match('^(.*[\\/])')
local ok,err=dofile(root..'lib/integration.lua').install(reaper,root)
if not ok then reaper.MB(err,'Fluent MIDI Editor',0) return end
dofile(root..'Fluent MIDI Editor - Open.lua')
