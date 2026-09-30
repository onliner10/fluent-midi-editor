-- Painting steps left to right in Steps mode draws a staircase. Every point
-- stored in the clip lies on that staircase; none keep the lane's old value,
-- where they would be drawn and grabbed away from the curve.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item=T.midi_item(0,8,{{60,0,1}},'Keys')
local S,M=T.session(item)
local A=T.load('modulation')
local lane=A.new_lane(0,1,0,4,.5); lane.mode='steps'
-- One drag across eight 1/16 cells, as modulation_ui paints it.
for i=0,7 do A.paint(lane,i*.25,i*.25+.25,i/8) end
local _,bykey=T.write_lane(S,lane)
local stored=bykey[A.key(0,1)]
local stray={}
for _,p in ipairs(stored.points) do
  local at,before=A.value(stored,p.t),A.value(stored,p.t-1e-4)
  if math.abs(p.v-at)>1e-3 and math.abs(p.v-before)>1e-3 then
    stray[#stray+1]=string.format('(%.2f, %.2f) on a curve at %.2f',p.t,p.v,at)
  end
end
T.eq(#stray,0,'points off the painted steps: '..table.concat(stray,' '))
print('painted steps have no stray points')
