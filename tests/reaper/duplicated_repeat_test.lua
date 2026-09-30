-- Duplicating a repeat item in REAPER (Item: Duplicate items) copies its
-- extstate. The duplicate moved to another track is an ordinary clip there
-- and must not block later edits of the original phrase.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local call=T.midi_item(0,4,{{60,0,1}},'Call')
local response=T.midi_item(0,8,{{48,0,1}},'Response')
local other=select(3,T.midi_item(16,4,{},'Other'))
local M=T.load('model')
local S=T.load('session').new(r,M,T.load('backend'),T.load('repetition'),T.load('phrase'))
S:attach({call,response})
T.ok(S:set_repeating(true,false))
local copy=r.GetTrackMediaItem(r.GetTrack(0,0),1)
T.ok(copy,'repeat item')
T.select(copy)
r.Main_OnCommand(41295,0) -- Item: Duplicate items
local duplicate=r.GetSelectedMediaItem(0,0)
T.ok(duplicate and duplicate~=copy,'duplicate')
r.MoveMediaItemToTrack(duplicate,other)
r.SetMediaItemInfo_Value(duplicate,'D_POSITION',r.TimeMap2_QNToTime(0,24))
r.Undo_OnStateChange('Test: move duplicate')
S:attach({r.GetTrackMediaItem(r.GetTrack(0,0),0),r.GetTrackMediaItem(r.GetTrack(0,1),0)})
local notes=M.copy(S.notes)
for _,n in ipairs(notes) do if n.take_index==1 then n.pitch=n.pitch+1 end end
local ok,message=S:commit(notes,'Transpose')
T.ok(ok,'edit after duplicating a repeat: '..tostring(message))
print('a duplicated repeat does not block edits')
