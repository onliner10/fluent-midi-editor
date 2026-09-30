-- A new MIDI item is one bar with Loop source on. Stretched to two bars in the
-- arrange view before anything is drawn, it is a two-bar clip, not a one-bar
-- phrase played twice: its source is empty, so there is nothing to repeat.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item,take=T.midi_item(0,4,{},'Keys')
r.SetMediaItemInfo_Value(item,'D_LENGTH',r.TimeMap2_QNToTime(0,8))
r.Undo_OnStateChange('Test: stretch empty clip')
T.eq(r.GetMediaItemInfo_Value(item,'B_LOOPSRC'),1,'new clips loop their source')
local M=T.load('model')
local S=T.load('session').new(r,M,T.load('backend'),T.load('repetition'),T.load('phrase'))
S:attach({item})
local b=S.clips[1]
T.eq(b.single,true,'plain clip'); T.eq(b.length,8,'phrase length')
T.eq(b.native_cycles,1,'source passes'); T.eq(#b.repeats,0,'repeats')
-- A note in the second bar is written into the source, not into a repeat.
T.ok(S:commit({{s=5,e=6,pitch=64,vel=100,channel=0,selected=true,muted=false,take_index=1}},'Add note'))
b=S.clips[1]
T.eq(b.source.end_ppq,8*960,'source grows to the clip')
T.eq(r.TimeMap2_timeToQN(0,r.GetMediaItemInfo_Value(item,'D_LENGTH')),8,'clip length')
T.eq(#T.notes(r.GetActiveTake(item)),1,'notes in the source')
T.eq(b.native_cycles,1,'source passes after the note')
T.eq(#S.notes,1,'editable notes')
print('a stretched empty clip is one plain clip')
