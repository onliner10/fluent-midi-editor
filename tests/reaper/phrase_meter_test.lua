-- Phrase length is in bars of the project's meter, counted from where the
-- clip starts, across meter and tempo changes.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
local L=T.load('length')
local function length(item) return r.TimeMap2_timeToQN(0,r.GetMediaItemInfo_Value(item,'D_LENGTH')+r.GetMediaItemInfo_Value(item,'D_POSITION'))
  -r.TimeMap2_timeToQN(0,r.GetMediaItemInfo_Value(item,'D_POSITION')) end
T.reset()
-- 4/4, then 3/4 from bar 2.
r.SetTempoTimeSigMarker(0,-1,r.TimeMap2_QNToTime(0,4),-1,-1,120,3,4,false); r.UpdateTimeline()
local item=T.midi_item(0,7,{{60,0,1},{62,4,5}},'Keys')
local S=T.session(item)
T.eq(L.format(L.phrase_bars(r,S.clips[1])),'2','4/4 bar and 3/4 bar')
T.ok(S:resize_phrase(L,1,false)); T.eq(length(item),4,'1 bar of 4/4')
T.ok(S:resize_phrase(L,3,false)); T.eq(length(item),10,'4/4 + two 3/4 bars')
T.ok(S:resize_phrase(L,1.5,false)); T.eq(length(item),5.5,'4/4 + half a 3/4 bar')
T.reset()
-- A clip starting mid-bar counts bars from its start; a tempo change inside
-- it changes seconds, not beats.
r.SetTempoTimeSigMarker(0,-1,r.TimeMap2_QNToTime(0,6),-1,-1,60,-1,-1,false); r.UpdateTimeline()
item=T.midi_item(1.5,4,{{60,0,1}},'Keys'); S=T.session(item)
T.ok(S:resize_phrase(L,2,false)); T.eq(length(item),8,'2 bars from beat 1.5')
T.ok(S:resize_phrase(L,0.5,false)); T.eq(length(item),2,'half a bar')
T.reset()
print('phrase length follows meter and tempo')
