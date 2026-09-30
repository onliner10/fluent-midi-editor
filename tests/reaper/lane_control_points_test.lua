-- Ctrl+D copies a modulation curve. Deleting a point in the copy then gives
-- the same curve as deleting it in the original: the copy must not keep
-- control points of the segment that no longer exists.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item=T.midi_item(0,4,{{60,0,1}},'Keys')
r.SetMediaItemInfo_Value(item,'B_LOOPSRC',0)
local S=T.session(item)
local A=T.load('modulation')
local lane=A.new_lane(0,1,0,4,0)
lane.points={{t=0,v=0,kind=0,bend=0},{t=1,v=1,kind=2,bend=0},{t=2,v=0,kind=0,bend=0},{t=4,v=0,kind=0,bend=0}}
T.write_lane(S,lane)
-- editor.lua duplicate(): copy [0,4), insert at 4, the phrase grows to 8.
local b=S.clips[1]
local fragment=A.copy_range(b.source,b.to_ppq(0),b.to_ppq(4))
local ending=8
local raw=A.insert_range(b.source,fragment,b.to_ppq(4),math.max(b.source.end_ppq,b.to_ppq(ending)))
local notes=T.load('model').copy(S.notes)
T.ok(S:commit(notes,'Duplicate phrase with modulation',8,{[1]={raw=raw,ending=ending}}))
b=S.clips[1]
local problems={}
-- Delete the copied peak at t=5, as the Delete key in the lane does.
local _,bykey=T.lanes(S)
local copy=T.load('model').copy(bykey[A.key(0,1)])
for i=#copy.points,1,-1 do if math.abs(copy.points[i].t-5)<1e-3 then table.remove(copy.points,i) end end
_,bykey=T.write_lane(S,copy)
local value=A.value(bykey[A.key(0,1)],5)
if math.abs(value)>0.02 then problems[#problems+1]=string.format('after deleting the copied peak the curve is %.3f at its place, not 0',value) end
T.eq(#problems,0,table.concat(problems,'; '))
print('deleting a copied point leaves a clean curve')
