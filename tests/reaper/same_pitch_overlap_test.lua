-- Dragging a short note onto a long note of the same pitch keeps the length
-- of the note that was dragged, and the editor shows what REAPER stores.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local item=T.midi_item(0,8,{{60,0,4},{60,5,6}},'Keys')
local M=T.load('model')
local S=T.load('session').new(r,M,T.load('backend'),T.load('repetition'),T.load('phrase'))
S:attach({item})
local notes=M.copy(S.notes)
for _,n in ipairs(notes) do if n.s==5 then n.s,n.e=1,2 end end
T.ok(S:commit(notes,'Move notes'))
local function describe(list)
  local out={}; for _,n in ipairs(list) do out[#out+1]=string.format('%g-%g',n.s or n[2],n.e or n[3]) end
  table.sort(out); return table.concat(out,' ')
end
local editor=describe(S.notes)
local native=describe(T.notes(r.GetActiveTake(S.clips[1].item)))
T.ok(editor:find('1%-2'),'dragged note 1-2 lost its length; editor shows '..editor)
T.eq(editor,native,'editor and REAPER disagree')
print('overlapping same-pitch notes keep their lengths')
