-- A new "+ CC" lane is flat at 0.5. Its CC stays at one value instead of
-- flickering between 63 and 64.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item=T.midi_item(0,16,{{60,0,1}},'Keys')
local S=T.session(item)
local A=T.load('modulation'); local b=S.clips[1]
T.write_lane(S,A.new_lane(0,1,b.edit_source_start,b.edit_source_end,.5))
local values={}
for _,e in ipairs(T.ccs(r.GetActiveTake(S.clips[1].item))) do values[e[4]]=(values[e[4]] or 0)+1 end
local list={}; for v,n in pairs(values) do list[#list+1]=v..' x'..n end; table.sort(list)
T.eq(#list,1,'distinct CC values in a flat lane ('..table.concat(list,', ')..')')
print('flat lane writes one value')
