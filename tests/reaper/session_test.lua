-- A session edits real takes on two tracks as one Undo step.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local lead=T.midi_item(0,4,{{60,0,1},{64,1,2}},'Lead')
local bass=T.midi_item(0,4,{{48,0,2}},'Bass')
local M=T.load('model')
local S=T.load('session').new(r,M,T.load('backend'),T.load('repetition'),T.load('phrase'))
T.select(lead,bass)
S:attach(S:selected_items())
T.eq(#S.clips,2,'clips'); T.eq(#S.notes,3,'notes')

local notes=M.copy(S.notes)
for _,n in ipairs(notes) do n.pitch=n.pitch+1 end
T.ok(S:commit(notes,'Transpose'))
-- Undo replaces track and item pointers, so look clips up by track index.
local function pitches(track)
  local out={}; for _,n in ipairs(T.notes(r.GetActiveTake(r.GetTrackMediaItem(r.GetTrack(0,track),0)))) do out[#out+1]=n[1] end
  return table.concat(out,',')
end
T.eq(pitches(0),'61,65','lead after edit'); T.eq(pitches(1),'49','bass after edit')
T.eq(r.Undo_CanUndo2(0),'Fluent MIDI Editor: Transpose','undo label')

r.Undo_DoUndo2(0)
T.eq(pitches(0),'60,64','lead after undo'); T.eq(pitches(1),'48','bass after undo')
print('3 notes on 2 clips, one undo step')
