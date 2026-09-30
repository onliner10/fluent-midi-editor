-- A curve the editor has just written is not reported as "CC changed outside
-- Fluent MIDI Editor". Unsnapped point drags are the default, so points land
-- between ticks.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item=T.midi_item(0,16,{{60,0,1}},'Keys')
local S=T.session(item)
local A=T.load('modulation')
local stale={}
for k=0,19 do
  local t=1+k*0.00037 -- a middle point dragged to an arbitrary time
  local lane=A.new_lane(0,1,0,4,.5)
  lane.points={{t=0,v=.2,kind=0,bend=0},{t=t,v=.3,kind=0,bend=.5},{t=1.5,v=.6,kind=0,bend=0},{t=4,v=.5,kind=0,bend=0}}
  local _,bykey=T.write_lane(S,lane)
  if bykey[A.key(0,1)].stale then stale[#stale+1]=string.format('%.5f',t) end
end
T.eq(#stale,0,'lanes stale right after writing, middle point at '..table.concat(stale,', '))
print('written curves match their CC')
