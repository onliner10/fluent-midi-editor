-- A clip whose start was trimmed in the arrange view plays one pass of its
-- source: it is a plain clip. Its length counts from where it starts, a new
-- length keeps Loop source and the trim, Repeat phrase stays off, and ×2
-- copies what is visible, not the trimmed-off head.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item,take=T.midi_item(0,8,{{60,0,1},{62,2,3}},'Keys')
r.SetMediaItemInfo_Value(item,'D_POSITION',r.TimeMap2_QNToTime(0,1))
r.SetMediaItemInfo_Value(item,'D_LENGTH',r.TimeMap2_QNToTime(0,7))
r.SetMediaItemTakeInfo_Value(take,'D_STARTOFFS',r.TimeMap2_QNToTime(0,1))
r.UpdateItemInProject(item); r.Undo_OnStateChange('Test: trim clip start')
local S=T.session(item); local L=T.load('length')
local b=S.clips[1]
T.eq(b.single,true,'a trimmed clip is plain'); T.eq(S.clips[1].native_cycles,1,'source passes')
T.eq(L.format(L.phrase_bars(r,b)),'1,75','phrase length of 7 beats')
T.eq(#S.notes,1,'only the note after the trim is visible')
local function check(label,length,notes)
  T.eq(r.TimeMap2_timeToQN(0,r.GetMediaItemInfo_Value(item,'D_LENGTH')),length,label..': clip length')
  T.eq(r.GetMediaItemInfo_Value(item,'B_LOOPSRC'),1,label..': Loop source')
  T.eq(r.TimeMap2_timeToQN(0,r.GetMediaItemTakeInfo_Value(r.GetActiveTake(item),'D_STARTOFFS')),1,label..': trim')
  T.eq(S.clips[1].repeating,false,label..': Repeat phrase')
  local got={}; for _,n in ipairs(T.notes(r.GetActiveTake(item))) do got[#got+1]=n[1]..'@'..n[2] end
  T.eq(table.concat(got,' '),notes,label..': notes in the source')
end
T.ok(S:resize_phrase(L,1,false)); check('1 bar',4,'60@0.0 62@2.0')
T.ok(S:resize_phrase(L,2,false,true)); check('×2',8,'60@0.0 62@2.0 62@6.0')
T.ok(S:resize_phrase(L,3,false)); check('3 bars',12,'60@0.0 62@2.0 62@6.0')
print('a trimmed clip changes length like a plain clip')
