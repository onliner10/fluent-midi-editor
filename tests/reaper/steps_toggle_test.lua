-- Curve / Steps changes the drawing mode of the lane. The mode is part of the
-- lane stored in the clip, so it is still set when the clip is read again.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item=T.midi_item(0,8,{{60,0,1}},'Keys')
local S=T.session(item); local A=T.load('modulation')
local lane=A.new_lane(0,1,0,8,.3,'Cutoff')
lane.points={{t=0,v=.2,kind=0,bend=0},{t=4,v=.8,kind=0,bend=0},{t=8,v=.3,kind=0,bend=0}}
T.write_lane(S,lane)
T.select(r.GetTrackMediaItem(r.GetTrack(0,0),0))
return T.steps(T.concat(T.open_steps(),
  function() local w=T.window(); return T.click_steps(w[1]+338,w[2]+523) end,
  1.0,
  function()
    T.close_editor()
    local _,bykey=T.lanes(T.session(r.GetTrackMediaItem(r.GetTrack(0,0),0)))
    T.eq(bykey[A.key(0,1)].mode,'steps','lane mode stored in the clip after clicking Steps')
    print('Steps is stored with the lane')
    return true
  end))
