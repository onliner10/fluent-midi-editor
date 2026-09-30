-- Ctrl+D on a clip with a modulation lane, done the way the editor does it.
-- The copied curve's end knot stays inside the MIDI source (one tick before
-- the end, flagged +1). A knot on the end tick itself is dropped when REAPER
-- or the phrase code trims or repeats the source, and the curve's end is lost.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
-- A playrate that makes beat-to-tick conversions inexact.
local item,take=T.midi_item(0,4,{{60,0,1}},'Keys')
r.SetMediaItemInfo_Value(item,'B_LOOPSRC',0)
r.SetMediaItemTakeInfo_Value(take,'D_PLAYRATE',1.3333)
r.Undo_OnStateChange('Test: playrate')
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
for _,e in ipairs(b.source.events) do
  local fields=A.meta(e.msg)
  if fields and fields[1]=='P' and e.pos>=b.source.end_ppq then
    problems[#problems+1]='knot at tick '..e.pos..' is not inside the source (end '..b.source.end_ppq..')'
  end
end
T.eq(#problems,0,table.concat(problems,'; '))
print('duplicated lane keeps its end knot inside the source')
