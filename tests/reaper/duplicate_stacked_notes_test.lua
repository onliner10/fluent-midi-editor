-- Two notes of one pitch starting together (a recording can leave them)
-- duplicate like any others. Overlap resolution used to shorten one of them
-- to nothing in place, so the commit refused "A note is shorter than one MIDI
-- tick" with a traceback.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item=T.midi_item(0,8,{{71,1,1.5},{71,1,2.75},{59,1.25,3}},'Keys')
local S,M=T.session(item)
local notes=M.copy(S.notes); for _,n in ipairs(notes) do n.selected=true end
local range=M.duplicate(notes,0,{1,3})
local ok,message=S:commit(notes,'Duplicate',range[2])
T.ok(ok,'duplicate: '..tostring(message))
local copies={}
for _,n in ipairs(T.notes(r.GetActiveTake(item))) do if n[2]>=3 then copies[#copies+1]=n[1]..'@'..n[2]..'-'..n[3] end end
T.eq(table.concat(copies,' '),'71@3.0-4.75 59@3.25-5.0','copies')
print('stacked notes of one pitch duplicate')
