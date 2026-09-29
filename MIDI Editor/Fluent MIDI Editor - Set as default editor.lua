-- @noindex
local root=debug.getinfo(1,'S').source:sub(2):match('^(.*[\\/])')
dofile(root..'lib/integration.lua').install(reaper,root)
dofile(root..'Fluent MIDI Editor - Open.lua')
