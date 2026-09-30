-- ×2 doubles a plain clip: the notes are copied into the new half and the
-- loop is set to the new length. Repeat phrase stays off. Halving hides the
-- second half again without deleting it, and Loop source stays on throughout.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item=T.midi_item(0,4,{{60,0,1},{64,1,2},{67,2,3},{72,3,4}},'Keys')
local S=T.session(item)
local L=T.load('length')
local track=r.GetTrack(0,0)
local function state()
  local it=r.GetTrackMediaItem(track,0)
  return #T.notes(r.GetActiveTake(it)),r.TimeMap2_timeToQN(0,r.GetMediaItemInfo_Value(it,'D_LENGTH')),
    r.GetMediaItemInfo_Value(it,'B_LOOPSRC'),r.CountTrackMediaItems(track)
end
T.ok(S:resize_phrase(L,2,false,true))
local notes,length,loop,clips=state()
T.eq(notes,8,'notes after ×2'); T.eq(length,8,'clip length after ×2'); T.eq(loop,1,'Loop source after ×2')
T.eq(clips,1,'clips after ×2'); T.eq(S.clips[1].repeating,false,'Repeat phrase after ×2')
T.eq(S.clips[1].source.end_ppq,8*960,'loop length after ×2')
T.eq(#S.notes,8,'editable notes after ×2')
T.ok(S:resize_phrase(L,1,false))
notes,length,loop,clips=state()
T.eq(length,4,'clip length after ÷2'); T.eq(loop,1,'Loop source after ÷2'); T.eq(#S.notes,4,'visible notes after ÷2')
T.eq(notes,8,'the hidden half stays in the clip')
T.eq(#S.ghosts,0,'a trimmed clip shows no repeats')
print('×2 duplicates the notes and loops at the new length')
