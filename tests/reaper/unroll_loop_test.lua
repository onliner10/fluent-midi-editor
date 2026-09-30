-- Clicking a loop pass of a clip that loops its source makes the whole clip
-- editable: the passes are written out, the clip sounds the same, and Phrase
-- repeat stays off.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item=T.midi_item(0,4,{{60,0,1}},'Keys')
r.SetMediaItemInfo_Value(item,'D_LENGTH',r.TimeMap2_QNToTime(0,8))
r.Undo_OnStateChange('Test: loop source twice')
local M=T.load('model'); local L=T.load('length')
local S=T.load('session').new(r,M,T.load('backend'),T.load('repetition'),T.load('phrase'))
S:attach({item})
T.eq(S.clips[1].native_cycles,2,'source passes before')
T.ok(S:unroll(L,1,false))
local b=S.clips[1]
T.eq(r.CountTrackMediaItems(r.GetTrack(0,0)),1,'clips')
T.eq(r.TimeMap2_timeToQN(0,r.GetMediaItemInfo_Value(b.item,'D_LENGTH')),8,'clip length')
local notes=T.notes(b.take)
T.eq(#notes,2,'notes written out'); T.eq(notes[2][2],4,'second pass note')
T.eq(b.native_cycles,1,'source passes after'); T.eq(b.repeating,false,'Phrase repeat')
T.eq(b.length,8,'phrase length'); T.eq(#S.notes,2,'editable notes'); T.eq(#S.ghosts,0,'repeats')
print('a looped clip unrolls into one editable phrase')
