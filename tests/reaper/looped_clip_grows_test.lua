-- A note added past the end of a clip that was shortened in the arrange view
-- makes the clip grow, like any regular clip (guide: "Regular clips, including
-- ones with a single source loop enabled, grow when the copy extends past
-- their end"). The note must stay visible and audible, not land in the hidden
-- part of the looped source.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
-- New MIDI clips loop their source; shortening shows part of one cycle.
local item=T.midi_item(0,16,{{60,0,1}},'Keys')
r.SetMediaItemInfo_Value(item,'D_LENGTH',r.TimeMap2_QNToTime(0,8))
r.Undo_OnStateChange('Test: shorten clip')
local M=T.load('model')
local S=T.load('session').new(r,M,T.load('backend'),T.load('repetition'),T.load('phrase'))
S:attach({item})
local notes=M.copy(S.notes)
notes[#notes+1]={s=9,e=10,pitch=64,vel=100,channel=0,selected=true,muted=false,take_index=1}
T.ok(S:commit(notes,'Add note',10))
local visible=false
for _,n in ipairs(S.notes) do if n.pitch==64 then visible=true end end
local item_end=r.TimeMap2_timeToQN(0,r.GetMediaItemInfo_Value(S.clips[1].item,'D_LENGTH'))
T.ok(item_end>=10-1e-6,'clip should grow to 10 QN to hold the note, ends at '..item_end)
T.ok(visible,'the added note is missing from the editor')
print('clip grows to hold a note past its end')
