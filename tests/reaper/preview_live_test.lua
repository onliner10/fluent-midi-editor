-- Preview: the instrument track runs live (no media buffering, no anticipative
-- FX) while Preview is on and gets its own flags back afterwards, even after
-- a crash. Selecting more notes layers them instead of cutting the first off.
-- SWS is stubbed: the headless REAPER has none, and only the calls matter here.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local _,_,track=T.midi_item(0,4,{},'Keys')
r.SetMediaTrackInfo_Value(track,'I_PERFFLAGS',0)
local playing,stopped=0,0
local sws=setmetatable({
  CF_CreatePreview=function() return {} end,
  CF_Preview_SetOutputTrack=function() return true end,
  CF_Preview_Play=function() playing=playing+1; return true end,
  CF_Preview_Stop=function() stopped=stopped+1 end,
},{__index=r})
local P=T.load('preview')
local function flags() return math.floor(r.GetMediaTrackInfo_Value(track,'I_PERFFLAGS')) end

local A=P.new(sws)
A:live(0,track)
T.eq(flags(),3,'live while Preview is on')
A:live(nil,nil)
T.eq(flags(),0,'own flags back')

A:play(0,track,{{pitch=60,vel=100,channel=0,sec=1}})
T.eq(flags(),3,'playing makes the track live')
A:play(0,track,{{pitch=64,vel=100,channel=0,sec=1}},false,true)
T.ok(A:sounding(60) and A:sounding(64),'a layered note keeps the first one sounding')
T.eq(stopped,0,'layering stops nothing')
A:play(0,track,{{pitch=67,vel=100,channel=0,sec=1}})
T.ok(A:sounding(67) and not A:sounding(60),'a new click cuts what was sounding')
A:close()
T.eq(flags(),0,'closing gives the flags back')

-- An editor that crashed with Preview on leaves the saved flags behind.
r.SetMediaTrackInfo_Value(track,'I_PERFFLAGS',2)
P.new(sws):live(0,track)
T.eq(flags(),3,'live')
P.new(sws)
T.eq(flags(),2,'the next editor restores the flags')
print('preview runs the track live and layers selected notes')
