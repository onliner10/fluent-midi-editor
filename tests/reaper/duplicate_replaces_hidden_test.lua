-- Ctrl+D into the part of a clip a shortening hid puts the copy there, not
-- the copy plus the notes that were hidden. Hidden notes past the copy stay
-- in the clip and come back when it is lengthened.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item=T.midi_item(0,12,{{60,0,1},{64,4,5},{67,6,7},{72,9,10}},'Keys')
local S,M=T.session(item); local L=T.load('length')
T.ok(S:resize_phrase(L,1,false))
local notes=M.copy(S.notes); for _,n in ipairs(notes) do n.selected=true end
local range=M.duplicate(notes,0,{0,4})
T.ok(S:commit(notes,'Duplicate',range[2]))
local function shown()
  local t={}; for _,n in ipairs(S.notes) do t[#t+1]=n.pitch..'@'..n.s end; table.sort(t); return table.concat(t,' ')
end
T.eq(shown(),'60@0.0 60@4.0','after Ctrl+D')
T.ok(S:resize_phrase(L,3,false))
T.eq(shown(),'60@0.0 60@4.0 72@9.0','after lengthening to 3 bars')
print('Ctrl+D replaces notes hidden where the copy lands')
