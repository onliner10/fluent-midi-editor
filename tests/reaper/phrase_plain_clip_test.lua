-- Lengthening the phrase of a plain clip adds empty space; it neither copies
-- notes nor turns on Repeat phrase (guide: "Without repeat, lengthening adds
-- empty space"). REAPER creates MIDI items with Loop source on, and a single
-- cycle of the source is still a plain clip.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item=T.midi_item(0,16,{{60,0,1},{62,4,5}},'Keys')
T.eq(r.GetMediaItemInfo_Value(item,'B_LOOPSRC'),1,'new clips loop their source')
local M=T.load('model')
local S=T.load('session').new(r,M,T.load('backend'),T.load('repetition'),T.load('phrase'))
S:attach({item})
T.eq(S.clips[1].repeating,false,'repeat before')
T.ok(S:resize_phrase(T.load('length'),8,false))
local track=r.GetTrack(0,0)
local count=0
for i=0,r.CountTrackMediaItems(track)-1 do count=count+#T.notes(r.GetActiveTake(r.GetTrackMediaItem(track,i))) end
T.eq(S.clips[1].repeating,false,'Repeat phrase after lengthening')
T.eq(count,2,'notes on the track after lengthening 4 -> 8 bars')
print('lengthening adds empty space')
