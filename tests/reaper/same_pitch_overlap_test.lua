-- MIDI cannot hold two sounding notes of one pitch on one channel. As in
-- Ableton, a note dragged over the end of another shortens it, and a note
-- dragged over the start of another replaces it. The dragged note keeps its
-- length, and the editor shows what REAPER stores.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
local function describe(list)
  local out={}; for _,n in ipairs(list) do out[#out+1]=string.format('%g-%g',n.s or n[2],n.e or n[3]) end
  table.sort(out); return table.concat(out,' ')
end
local function drag(existing,from,to)
  T.reset()
  local item=T.midi_item(0,8,existing,'Keys')
  local S,M=T.session(item)
  local notes=M.copy(S.notes)
  for _,n in ipairs(notes) do if n.s==from then n.e=to+n.e-n.s; n.s=to end end
  T.ok(S:commit(notes,'Move notes'))
  local editor,native=describe(S.notes),describe(T.notes(r.GetActiveTake(S.clips[1].item)))
  T.eq(editor,native,'editor and REAPER disagree')
  return editor
end
-- Over the end of a long note: it is shortened to where the dragged note starts.
T.eq(drag({{60,0,4},{60,5,6}},5,1),'0-1 1-2','drag a short note to beat 1 over a note 0-4')
-- Over the start of a note: that note is replaced.
T.eq(drag({{60,2,4},{60,5,6}},5,1.5),'1.5-2.5','drag a note to beat 1.5 over a note 2-4')
print('overlapping same-pitch notes follow the Ableton rule')
