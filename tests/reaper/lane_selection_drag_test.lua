-- A selected modulation point stays selected after it is dragged, so the
-- next gesture (another drag, or Delete) still applies to it. Unsnapped drags
-- are the default and leave the point between ticks.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item=T.midi_item(0,8,{{60,0,1}},'Keys')
local S=T.session(item); local A=T.load('modulation')
local lane=A.new_lane(0,1,0,8,.3,'Cutoff')
lane.points={{t=0,v=.2,kind=0,bend=0},{t=4,v=.8,kind=0,bend=0},{t=8,v=.3,kind=0,bend=0}}
T.write_lane(S,lane)
T.select(r.GetTrackMediaItem(r.GetTrack(0,0),0))
local DRAG=true
return T.steps(T.concat(T.open_steps(),
  function()
    -- The middle point (beat 4, value 0.8). The graph shares the piano roll's
    -- timeline, which shows the 8-beat clip from 0 to 8.5 when it opens.
    local g=T.control('graph'); local px,py=math.floor(g[1]+4/8.5*(g[3]-g[1])),math.floor(g[2]+0.2*(g[4]-g[2]))
    local steps=T.drag_steps(px-25,py-24,px+25,py+9) -- rectangle around it
    if DRAG then steps=T.concat(steps,T.drag_steps(px,py,px+37,py+10)) end
    return T.concat(steps,{function() T.keys('Delete'); return true end,0.8})
  end,
  function()
    T.close_editor()
    local _,bykey=T.lanes(T.session(r.GetTrackMediaItem(r.GetTrack(0,0),0)))
    T.eq(#bykey[A.key(0,1)].points,2,'points after selecting, dragging and deleting the middle point')
    print('a dragged point stays selected')
    return true
  end))
