-- A clip that loops its source several times shows the first pass for editing
-- and the rest as read-only repeats (guide: "a 4-bar clip can contain a 2-bar
-- phrase played twice: the field shows 2, and the grid shows the original and
-- the repeat").
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item=T.midi_item(0,8,{{60,0,1}},'Keys')
r.SetMediaItemInfo_Value(item,'D_LENGTH',r.TimeMap2_QNToTime(0,16))
r.Undo_OnStateChange('Test: loop source twice')
local M=T.load('model')
local S=T.load('session').new(r,M,T.load('backend'),T.load('repetition'),T.load('phrase'))
S:attach({item})
T.eq(S.clips[1].native_cycles,2,'source cycles')
T.eq(#S.ghosts,1,'repeated notes shown')
T.eq(S.show_repeats,true,'repeats shown')
T.eq(S.view_length,16,'visible length')
print('native loop shows its repeat')
